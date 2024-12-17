# Cypache
A lightning-fast and modular Python3 webserver written in Cython, known for handling especially large HTTP loads.

# Performance

| Name | Requests/s | Type |
| --- | --- | --- |
| Cypache with fastepoll w/ sync | 216277 | Synced connections in Cython/C++* w/ file reading and full HTTP headers parsing |
| Nginx | 364761 | Written entirely in C/C++ |
| Cypache with fastepoll w/ desync | 500667 | Desynced connections in Cython/C++** w/ file reading and full HTTP headers parsing + resolvpath |

\* Synced connections = all calls on the same thread resulting in a shared Python state across threads
\*\* Desynced connections = calls on different threads resulting in different Python states between calls

# Warning
Cypache is currently under development and is NOT suitable for production, only for testing.
