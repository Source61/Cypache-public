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