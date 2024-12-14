#!/usr/bin/env python3
from socket import socket
import sys

addr = sys.argv[1]
port = 80
uri = ""
if addr.find("/") != -1:
	addr,uri = addr.split("/", 1)
if addr.find(":") != -1:
	addr,port = addr.split(":")
uri = "/" + uri
data = b"GET %b HTTP/1.0\r\nHost: %b\r\n\r\n" % (uri.encode(), addr.encode())
print("We're sending:", data)

s = socket()
s.connect((addr, int(port)))
s.send(data)
print(s.recv(10000))
