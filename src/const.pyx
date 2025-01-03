cdef:
  map[string, string] env = {
    b"Server": b"Cypache",
    b"Version": b"1.0.1",
  }
  map[int, string] statusCodes = {
    200: b"OK",
    400: b"Bad Request",
    404: b"Not Found",
  }

  unsigned long long maxFds
  unsigned long long maxFilepaths = 10000
  bool mvcPattern
  string wwwDir
  string appsDir
  string rewritePathsTo
  vector[string] indexes

  dict pyModules = {}