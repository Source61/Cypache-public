#!/usr/bin/env python3
from socket import socket
import sys

addr,port = sys.argv[1].split(":")
url = ""
if port.find("/") != -1:
	port,url = port.split("/", 1)
url = "/" + url
data = b"GET %b HTTP/1.0\r\nHost: %b\r\n\r\n" % (url.encode(), addr.encode())
#print("We're sending:", data)

s = socket()
s.connect((addr, int(port)))
s.send(data)
print(s.recv(10000))
