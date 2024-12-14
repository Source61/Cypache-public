import asyncio, resource, os, sys, time

sys.path.append('.')

from posix.stat cimport *
from posix.fcntl cimport *
from posix.unistd cimport *
from libc.stdlib cimport malloc, free

from libcpp cimport bool
from libcpp.map cimport map
from libcpp.string cimport string
from libcpp.vector cimport vector
from cython.operator cimport dereference as deref

include "const.pyx"

maxFds, maxPossibleFds = resource.getrlimit(resource.RLIMIT_NOFILE)

cdef unsigned int timenow = 0
cdef string timenow_string
cdef string response = b""

cdef:
  void fatalError(msg):
    print(msg)
    exit(1)

  struct sCachedFiledata:
    int fd
    unsigned int mtime
    string mtime_string
    unsigned int lastcheckmtime
    string data
  map[string, sCachedFiledata] cachedFiledata
  map[int, string] cachedFiledataReverse
  vector[int] fds

  struct sCachedFilepath:
    string path
    unsigned int lastchecktime
  map[string, sCachedFilepath] cachedFilepaths
  vector[string] filepaths

  int appendFd(string uri):
    cdef int fd = open(uri.c_str(), O_RDONLY)
    cdef int oldfd
    if fd == -1:
      return fd
    fds.push_back(fd)
    if fds.size() >= maxFds:
      oldfd = deref(fds.begin())
      close(oldfd)
      if cachedFiledataReverse.count(oldfd) and cachedFiledata.count(cachedFiledataReverse[oldfd]):
        cachedFiledata[cachedFiledataReverse[oldfd]].fd = -1
      fds.erase(fds.begin())
    if cachedFiledata.count(uri):
      cachedFiledata[uri].fd = fd
    return fd
  
  double getFileMtime(int fd):
    cdef:
      struct_stat ss
    fstat(fd, &ss)
    return ss.st_mtim.tv_sec + (ss.st_mtim.tv_nsec / 1000000000.0)
  
  string readCachedFiledata(int fd):
    cdef:
      char* charptr = <char*>malloc(1000000000)
      string s
      ssize_t readLen
    readLen = read(fd, charptr, 1000000000)
    if readLen != -1:
      s = string(charptr, readLen)
    free(charptr)
    return s
  
  # Need to redesign this function to support different HTTP status codes
  string httpGenerateHeaders(sCachedFiledata* cachedFiledataPtr, int statusCode):
    cdef string header
    cdef string body

    # Assign body first; we need it to know the content-length header
    if statusCode == 200 and cachedFiledataPtr:
      body.assign(cachedFiledataPtr.data)
    elif statusCode == 400:
      body.assign(b"<html>\r\n<head><title>400 Bad Request</title></head>\r\n<body>\r\n<center><h1>400 Bad Request</h1></center>\r\n<hr><center>%b/%b</center>\r\n</body>\r\n</html>\r\n" % (env[b"Server"], env[b"Version"]))
    elif statusCode == 404:
      body.assign(b"<html>\r\n<head><title>404 Not Found</title></head>\r\n<body>\r\n<center><h1>404 Not Found</h1></center>\r\n<hr><center>%b/%b</center>\r\n</body>\r\n</html>\r\n" % (env[b"Server"], env[b"Version"]))

    # Assign headers next
    header.assign(b"HTTP/1.0 %d %b\r\n" % (statusCode, statusCodes[statusCode]))
    header.append(b"Server: %b/%b\r\n" % (env[b"Server"], env[b"Version"]))
    header.append(b"Date: %b\r\n" % timenow_string)
    header.append(b"Content-Type: text/html\r\n")
    header.append(b"Content-Length: %d\r\n" % body.size())
    if cachedFiledataPtr:
      #if not cachedFiledataPtr.mtime_string.empty():
      #  header.append(b"Last-Modified: %b\r\n" % time.strftime("%a, %d %b %Y %T %Z", time.gmtime(cachedFiledataPtr.mtime)).encode())
      #else:
      header.append(b"Last-Modified: %b\r\n" % cachedFiledataPtr.mtime_string)
    header.append(b"Connection: keep-alive\r\n")
    header.append(b"Accept-Ranges: bytes\r\n\r\n")
    return header + body
    
class WebServer(asyncio.Protocol):
  def connection_made(self, transport):
    self.transport = transport

  def data_received(self, data: bytes):
    cdef:
      bool timeIsSame = True, found = False
      double newtime
      unsigned int newtimeint, checkMtime
      double lastmtime = 0.0
      int fd = -1, oldfd
      sCachedFiledata *cachedFiledataPtr
      sCachedFiledata cachedFiledataStruct
      sCachedFilepath *cachedFilepathPtr = NULL
      string httpUri
      string absHttpUri
      string filepathTmp
    global response, timenow, timenow_string
    # Parse HTTP Headers
    bufferlist = data.split(b'\r\n\r\n', 1)
    headersList, postData = bufferlist[0].split(b'\r\n'), bufferlist[1]
    httpMethod, httpUri, httpVersion = headersList[0].split(b' ')
    httpParams = [b'']
    if httpUri.find(b'?') != -1:
      httpUri, httpParams = httpUri.split(b'?', 1)
      httpParams = httpParams.split('&')

    httpUri = wwwDir + httpUri.lstrip(b"/")

    # Get time and buffer time_string if 1s has passed
    newtime = time.time()
    newtimeint = <unsigned int>newtime
    if newtimeint != timenow:
      timenow = newtimeint
      timenow_string = time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode()
      timeIsSame = False

    # Start handling URI

    # Cache paths; faster by another 20-25% at max capacity; lasts 1s as usual
    if cachedFilepaths.count(httpUri):
      cachedFilepathPtr = &cachedFilepaths[httpUri]
    if maxFilepaths and (cachedFilepathPtr == NULL or cachedFilepathPtr.lastchecktime != newtimeint):
      if not cachedFilepathPtr:
        if filepaths.size() >= maxFilepaths:
          filepathTmp = deref(filepaths.begin())
          cachedFilepaths.erase(filepathTmp)
          filepaths.erase(filepaths.begin())
        cachedFilepaths[httpUri] = sCachedFilepath(os.path.abspath(httpUri) + b"/", timenow)
        cachedFilepathPtr = &cachedFilepaths[httpUri]
      else:
        cachedFilepathPtr.lastchecktime = timenow
        cachedFilepathPtr.path = os.path.abspath(httpUri) + b"/"

    if maxFilepaths:
      absHttpUri.assign(cachedFilepathPtr.path) # os.path.abspath is faster than Posix's C realpath(...)
    else:
      absHttpUri = os.path.abspath(httpUri) + b"/"

    # 1. Ensure URI filepath is valid, else send 400 Invalid Request
    if not absHttpUri.startswith(wwwDir): # This too is actually slightly faster than C strncmp
      self.transport.send(httpGenerateHeaders(NULL, 400))
      return
    
    # Indexes
    elif os.path.isdir(absHttpUri):
      for index in indexes:
        if os.path.isfile(absHttpUri + index):
          httpUri = absHttpUri + index
          found = True
          break

    # Check if data is already cached
    if cachedFiledata.count(httpUri):
      cachedFiledataPtr = &cachedFiledata[httpUri]
      # Fd has been closed, lets reopen it
      if cachedFiledataPtr.fd == -1:
        fd = cachedFiledataPtr.fd = appendFd(httpUri)
      else:
        fd = cachedFiledataPtr.fd
      # File has been deleted
      if fd == -1:
        cachedFiledata.erase(httpUri)
        self.transport.send(response)
        return
      # Ensure at least 1 second has passed since the last mtime check (perf boost by only updating file once every second thus reducing calls to stat)
      if cachedFiledataPtr.lastcheckmtime < newtimeint:
        cachedFiledataPtr.lastcheckmtime = newtimeint
        checkMtime = <unsigned int>getFileMtime(fd)
        if checkMtime != cachedFiledataPtr.mtime:
          cachedFiledataPtr.mtime_string = time.strftime("%a, %d %b %Y %T %Z", time.gmtime(checkMtime)).encode()
        cachedFiledataPtr.mtime = checkMtime
        if cachedFiledataPtr.mtime == newtimeint:
          cachedFiledataPtr.data = readCachedFiledata(cachedFiledataPtr.fd)
      self.transport.send(httpGenerateHeaders(cachedFiledataPtr, 200))
      #b"""HTTP/1.0 200 OK\r\nServer: nginx/1.22.1\r\nDate: %b\r\nContent-Type: text/html\r\nContent-Length: %d\r\nLast-Modified: Fri, 15 Nov 2024 22:21:58 GMT\r\nConnection: keep-alive\r\nAccept-Ranges: bytes\r\n\r\n%b""" % (time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode(), cachedFiledataPtr.data.size(), cachedFiledataPtr.data))

    # Else: check if file exists and open a file descriptor for it for faster future checks 
    else:
      fd = cachedFiledataStruct.fd = appendFd(httpUri)
      if fd != -1:
        cachedFiledataStruct.data = readCachedFiledata(fd)
        cachedFiledataStruct.mtime = <unsigned int>getFileMtime(fd)
        cachedFiledataStruct.mtime_string = time.strftime("%a, %d %b %Y %T %Z", time.gmtime(cachedFiledataStruct.mtime)).encode()
        cachedFiledataStruct.lastcheckmtime = newtimeint
        cachedFiledata[httpUri] = cachedFiledataStruct
        cachedFiledataPtr = &cachedFiledata[httpUri]
        self.transport.send(httpGenerateHeaders(cachedFiledataPtr, 200))

      # File does not exist (404)
      else:
        #if not timeIsSame:
        #response = httpGenerateHeaders(NULL, 404)
        self.transport.send(httpGenerateHeaders(NULL, 404))
  
  def eof_received(self):
    pass
    #print("eof_received")


# Setup config
import config

if not hasattr(config, "wwwDir"): fatalError("Config.py: Missing required wwwDir entry.")
if type(config.wwwDir) == str: config.wwwDir = config.wwwDir.encode()
elif type(config.wwwDir) != bytes: fatalError("Config.py: wwwDir variable must be of type str or bytes.")
elif not os.path.isdir(config.wwwDir): fatalError("Config.py: wwwDir is not a path to a directory.")
cdef string wwwDir = os.path.abspath(config.wwwDir) + b"/"

cdef vector[string] indexes
if hasattr(config, "indexes"):
  if type(config.indexes) != list: fatalError("Config.py: The 'indexes' variable must be a list of str/bytes.")
  elif any([type(x) not in [bytes, str] for x in config.indexes]): fatalError("Config.py: The 'indexes' variable must be a list of str/bytes.")
  indexes = [x if type(x) == bytes else x.encode() for x in config.indexes]

if hasattr(config, "maxFds"):
  if type(config.maxFds) != int: fatalError("Config.py: The 'maxFds' variable must be of type int.")
  if config.maxFds > 0xFFFFFFFFFFFFFFFF or config.maxFds < -1 or config.maxFds == 0: fatalError("Config.py: The 'maxFds' value must be -1 or > 0 and < 0xFFFFFFFFFFFFFFFF")
  if config.maxFds != maxFds:
    if config.maxFds == -1:
      config.maxFds = maxPossibleFds
    resource.setrlimit(resource.RLIMIT_NOFILE, (config.maxFds, maxPossibleFds))
    maxFds = config.maxFds

if hasattr(config, "maxFilepaths"):
  if type(config.maxFilepaths) != int: fatalError("Config.py: The 'maxFilepaths' variable must be of type int.")
  if config.maxFilepaths > 0xFFFFFFFFFFFFFFFF or config.maxFilepaths < 0: fatalError("Config.py: The 'maxFilepaths' value must be >= 0 and < 0xFFFFFFFFFFFFFFFF")
  maxFilepaths = config.maxFilepaths

# Run
import fastepoll
fastepoll.run_forever(WebServer, ":::80", False)