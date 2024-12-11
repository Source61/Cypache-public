import asyncio, fastepoll, os, time

from posix.stat cimport *
#from libc.stdio cimport *
from posix.fcntl cimport *
from posix.unistd cimport *
from libc.stdlib cimport malloc, free

from libcpp.map cimport map
from libcpp.string cimport string
from libcpp.vector cimport vector
from cython.operator cimport dereference as deref

timenow = 0
response = b""

cdef:
  struct sFileData:
    int fd
    unsigned int mtime
    unsigned int lastcheckmtime
    string data
  map[string, sFileData] filedata
  map[int, string] filedataReverse
  vector[int] fds

  int appendFd(string uri):
    cdef int fd = open(uri.c_str(), O_RDONLY)
    cdef int oldfd
    if fd == -1:
      return fd
    fds.push_back(fd)
    if fds.size() >= 1024:
      oldfd = deref(fds.begin())
      close(oldfd)
      if filedataReverse.count(oldfd) and filedata.count(filedataReverse[oldfd]):
        filedata[filedataReverse[oldfd]].fd = -1
      fds.erase(fds.begin())
    if filedata.count(uri):
      filedata[uri].fd = fd
    return fd
  
  double getFileMtime(int fd):
    cdef:
      struct_stat ss
    fstat(fd, &ss)
    return ss.st_mtim.tv_sec + (ss.st_mtim.tv_nsec / 1000000000.0)
  
  string readFileData(int fd):
    cdef:
      char* charptr = <char*>malloc(1000000000)
      string s
      ssize_t readLen
    readLen = read(fd, charptr, 1000000000)
    if readLen != -1:
      s = string(charptr, readLen)
    free(charptr)
    return s

class WebServer(asyncio.Protocol):
  def connection_made(self, transport):
    self.transport = transport

  def data_received(self, data: bytes):
    cdef:
      double newtime
      unsigned int newtimeint
      double lastmtime = 0.0
      int fd, oldfd
      sFileData *fileDataPtr
      sFileData fileDataStruct
      string httpUri
    global response, timenow
    # Parse HTTP Headers
    bufferlist = data.split(b'\r\n\r\n', 1)
    headersList, postData = bufferlist[0].split(b'\r\n'), bufferlist[1]
    httpMethod, httpUri, httpVersion = headersList[0].split(b' ')
    httpUri = b"." + httpUri
    httpParams = b''
    if httpUri.find(b'?') != -1:
      httpUri, httpParams = httpUri.split(b'?', 1)

    # Get time
    newtime = time.time()
    newtimeint = <unsigned int>newtime

    # Check if data is already cached
    if filedata.count(httpUri):
      fileDataPtr = &filedata[httpUri]
      # Fd has been closed, lets reopen it
      if fileDataPtr.fd == -1:
        fd = fileDataPtr.fd = appendFd(httpUri)
      else:
        fd = fileDataPtr.fd
      # File has been deleted
      if fd == -1:
        filedata.erase(httpUri)
        self.transport.send(response)
        return
      # Ensure at least 1 second has passed since the last mtime check (perf boost by only updating file once every second thus reducing calls to stat)
      if fileDataPtr.lastcheckmtime < newtimeint:
        fileDataPtr.lastcheckmtime = newtimeint
        fileDataPtr.mtime = <unsigned int>getFileMtime(fd)
        if fileDataPtr.mtime == newtimeint:
          fileDataPtr.data = readFileData(fileDataPtr.fd)
      self.transport.send(b"""HTTP/1.0 200 OK\r\nServer: nginx/1.22.1\r\nDate: %b\r\nContent-Type: text/html\r\nContent-Length: %d\r\nLast-Modified: Fri, 15 Nov 2024 22:21:58 GMT\r\nConnection: keep-alive\r\nAccept-Ranges: bytes\r\n\r\n%b""" % (time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode(), fileDataPtr.data.size(), fileDataPtr.data))

    # Else: check if file exists and open a file descriptor for it for faster future checks 
    else:
      fd = fileDataStruct.fd = appendFd(httpUri)
      if fd != -1:
        fileDataStruct.data = readFileData(fd)
        fileDataStruct.mtime = <unsigned int>getFileMtime(fd)
        fileDataStruct.lastcheckmtime = newtimeint
        filedata[httpUri] = fileDataStruct
        self.transport.send(b"""HTTP/1.0 200 OK\r\nServer: nginx/1.22.1\r\nDate: %b\r\nContent-Type: text/html\r\nContent-Length: %d\r\nLast-Modified: Fri, 15 Nov 2024 22:21:58 GMT\r\nConnection: keep-alive\r\nAccept-Ranges: bytes\r\n\r\n%b""" % (time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode(), fileDataStruct.data.size(), fileDataStruct.data))

      # File does not exist ("404"/default page)
      else:
        if newtimeint != timenow:
          timenow = newtimeint
          response = b"""HTTP/1.0 200 OK\r\nServer: nginx/1.22.1\r\nDate: %b\r\nContent-Type: text/html\r\nContent-Length: 615\r\nLast-Modified: Fri, 15 Nov 2024 22:21:58 GMT\r\nConnection: keep-alive\r\nAccept-Ranges: bytes\r\n\r\n<!DOCTYPE html>\n<html>\n<head>\n<title>Welcome to nginx!</title>\n<style>\nhtml { color-scheme: light dark; }\nbody { width: 35em; margin: 0 auto;\nfont-family: Tahoma, Verdana, Arial, sans-serif; }\n</style>\n</head>\n<body>\n<h1>Welcome to nginx!</h1>\n<p>If you see this page, the nginx web server is successfully installed and\nworking. Further configuration is required.</p>\n\n<p>For online documentation and support please refer to\n<a href="http://nginx.org/">nginx.org</a>.<br/>\nCommercial support is available at\n<a href="http://nginx.com/">nginx.com</a>.</p>\n\n<p><em>Thank you for using nginx.</em></p>\n</body>\n</html>\n""" % time.strftime("%a, %d %b %Y %T %Z", time.gmtime(timenow)).encode()
        self.transport.send(response)
  
  def eof_received(self):
    pass
    #print("eof_received")

fastepoll.run_forever(WebServer, ":::80")
