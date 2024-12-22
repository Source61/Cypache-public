# Cypache
A lightning-fast and modular Python3 webserver written in Cython able to handle up to 68% larger HTTP loads (HTML) and 2059% larger HTTP loads (Python vs PHP w/ fastCGI) than Nginx using multiple CPU cores through the very fast Python3 module fastepoll.

# Performance

| Name | Requests/s | Type |
| --- | --- | --- |
| Nginx PHP | 29184 | Nginx with fastCGI PHP for "Hello World" page |
| Cypache HTML with fastepoll w/ sync | 216277 | Synced connections in Cython/C++* w/ file reading and full HTTP headers parsing |
| Nginx HTML | 364761 | Written entirely in C/C++ |
| Cypache HTML with fastepoll w/ desync | 613627 | Desynced connections in Cython/C++** w/ file reading and full HTTP headers parsing + resolvpath |
| Cypache Python3 code execution with fastepoll w/ desync | 601175 | Desynced connections in Cython/C++** w/ file reading and full HTTP headers parsing + resolvpath -> return data directly from a Python3 return statement |

\* Synced connections = all calls on the same thread resulting in a shared Python state across threads
\*\* Desynced connections = calls on different threads resulting in different Python states between calls

# Warning
Cypache is currently under development and is NOT suitable for production, only for testing.
