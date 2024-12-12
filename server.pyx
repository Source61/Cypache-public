import asyncio, fastepoll, os, time

from posix.stat cimport *
from posix.fcntl cimport *
from posix.unistd cimport *
from libc.stdlib cimport malloc, free

from libcpp cimport bool
from libcpp.map cimport map
from libcpp.string cimport string
from libcpp.vector cimport vector
from cython.operator cimport dereference as deref

import resource
cdef unsigned int maxFds = resource.getrlimit(resource.RLIMIT_NOFILE)[0]

cdef unsigned int timenow = 0
cdef string timenow_string
cdef string response = b""

cdef:
  struct scachedFiledata:
    int fd
    unsigned int mtime
    string mtime_string
    unsigned int lastcheckmtime
    string data
  map[string, scachedFiledata] cachedFiledata
  map[int, string] cachedFiledataReverse
  vector[int] fds

  int appendFd(string uri):
    cdef int fd = open(uri.c_str(), O_RDONLY)
    cdef int oldfd
    if fd == -1:
      return fd
    fds.push_back(fd)
    if fds.size()+1 >= maxFds:
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
  
  string readcachedFiledata(int fd):
    cdef:
      char* charptr = <char*>malloc(1000000000)
      string s
      ssize_t readLen
    readLen = read(fd, charptr, 1000000000)
    if readLen != -1:
      s = string(charptr, readLen)
    free(charptr)
    return s
  
  string httpGenerateHeaders(scachedFiledata* cachedFiledataPtr):
    cdef string header
    cdef string body
    if cachedFiledataPtr:
      body.assign(cachedFiledataPtr.data)
    else:
      body.assign(b"""<!DOCTYPE html>\n<html>\n<head>\n<title>Welcome to nginx!</title>\n<style>\nhtml { color-scheme: light dark; }\nbody { width: 35em; margin: 0 auto;\nfont-family: Tahoma, Verdana, Arial, sans-serif; }\n</style>\n</head>\n<body>\n<h1>Welcome to nginx!</h1>\n<p>If you see this page, the nginx web server is successfully installed and\nworking. Further configuration is required.</p>\n\n<p>For online documentation and support please refer to\n<a href="http://nginx.org/">nginx.org</a>.<br/>\nCommercial support is available at\n<a href="http://nginx.com/">nginx.com</a>.</p>\n\n<p><em>Thank you for using nginx.</em></p>\n</body>\n</html>\n""")
    header.assign(b"HTTP/1.0 200 OK\r\n")
    header.append(b"Server: Cypache/1.0.1\r\n")
    header.append(b"Date: %b\r\n" % timenow_string)
    header.append(b"Content-Type: text/html\r\n")
    header.append(b"Content-Length: %d\r\n" % body.size())
    if cachedFiledataPtr:
      if cachedFiledataPtr.mtime_string.empty():
        header.append(b"Last-Modified: %b\r\n" % time.strftime("%a, %d %b %Y %T %Z", time.gmtime(cachedFiledataPtr.mtime)).encode())
      else:
        header.append(b"Last-Modified: %b\r\n" % cachedFiledataPtr.mtime_string)
    header.append(b"Connection: keep-alive\r\n")
    header.append(b"Accept-Ranges: bytes\r\n\r\n")
    return header + body
    
class WebServer(asyncio.Protocol):
  def connection_made(self, transport):
    self.transport = transport

  def data_received(self, data: bytes):
    cdef:
      bool timeIsSame = True
      double newtime
      unsigned int newtimeint, checkMtime
      double lastmtime = 0.0
      int fd, oldfd
      scachedFiledata *cachedFiledataPtr
      scachedFiledata cachedFiledataStruct
      string httpUri
    global response, timenow
    # Parse HTTP Headers
    bufferlist = data.split(b'\r\n\r\n', 1)
    headersList, postData = bufferlist[0].split(b'\r\n'), bufferlist[1]
    httpMethod, httpUri, httpVersion = headersList[0].split(b' ')
    httpUri = b"." + httpUri # Obvious security issues here
    httpParams = [b'']
    if httpUri.find(b'?') != -1:
      httpUri, httpParams = httpUri.split(b'?', 1)
      httpParams = httpParams.split('&')

    # Get time
    newtime = time.time()
    newtimeint = <unsigned int>newtime
    if newtimeint != timenow:
      timenow = newtimeint
      timenow_string = time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode()
      timeIsSame = False

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
          cachedFiledataPtr.data = readcachedFiledata(cachedFiledataPtr.fd)
      self.transport.send(httpGenerateHeaders(cachedFiledataPtr))
      #b"""HTTP/1.0 200 OK\r\nServer: nginx/1.22.1\r\nDate: %b\r\nContent-Type: text/html\r\nContent-Length: %d\r\nLast-Modified: Fri, 15 Nov 2024 22:21:58 GMT\r\nConnection: keep-alive\r\nAccept-Ranges: bytes\r\n\r\n%b""" % (time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode(), cachedFiledataPtr.data.size(), cachedFiledataPtr.data))

    # Else: check if file exists and open a file descriptor for it for faster future checks 
    else:
      fd = cachedFiledataStruct.fd = appendFd(httpUri)
      if fd != -1:
        cachedFiledataStruct.data = readcachedFiledata(fd)
        cachedFiledataStruct.mtime = <unsigned int>getFileMtime(fd)
        cachedFiledataStruct.mtime_string = time.strftime("%a, %d %b %Y %T %Z", time.gmtime(checkMtime)).encode()
        cachedFiledataStruct.lastcheckmtime = newtimeint
        cachedFiledata[httpUri] = cachedFiledataStruct
        cachedFiledataPtr = &cachedFiledata[httpUri]
        self.transport.send(httpGenerateHeaders(cachedFiledataPtr))

      # File does not exist ("404"/default page)
      else:
        if not timeIsSame:
          #timenow = newtimeint
          response = httpGenerateHeaders(NULL)
          #response = b"""HTTP/1.0 200 OK\r\nServer: nginx/1.22.1\r\nDate: %b\r\nContent-Type: text/html\r\nContent-Length: 615\r\nLast-Modified: Fri, 15 Nov 2024 22:21:58 GMT\r\nConnection: keep-alive\r\nAccept-Ranges: bytes\r\n\r\n<!DOCTYPE html>\n<html>\n<head>\n<title>Welcome to nginx!</title>\n<style>\nhtml { color-scheme: light dark; }\nbody { width: 35em; margin: 0 auto;\nfont-family: Tahoma, Verdana, Arial, sans-serif; }\n</style>\n</head>\n<body>\n<h1>Welcome to nginx!</h1>\n<p>If you see this page, the nginx web server is successfully installed and\nworking. Further configuration is required.</p>\n\n<p>For online documentation and support please refer to\n<a href="http://nginx.org/">nginx.org</a>.<br/>\nCommercial support is available at\n<a href="http://nginx.com/">nginx.com</a>.</p>\n\n<p><em>Thank you for using nginx.</em></p>\n</body>\n</html>\n""" % time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode()
        self.transport.send(response)
  
  def eof_received(self):
    pass
    #print("eof_received")

fastepoll.run_forever(WebServer, ":::80", False)
