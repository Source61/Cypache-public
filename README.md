# Cypache
A lightning-fast and modular Python3 webserver written in Cython, known for handling especially large HTTP loads.

# Performance

| Name | Requests/s | Type |
| --- | --- | --- |
| Cypache with fastepoll 1.0.0 with sync | 216277 | Synced connections in Cython/C++* w/ file reading and full HTTP headers parsing |
| Nginx | 317789 | Written in C |
| Cypache with fastepoll 1.0.1 with desync | ? (tested on slower hardware only: 3x increase in perf from 116599 to 321850 - will test on same hardware next week) | Desynced connections in Cython/C++** w/ file reading and full HTTP headers parsing |

\* Synced connections = all calls on the same thread resulting in a shared Python state across threads
\** Desynced connections = calls on different threads resulting in different Python states between calls

# Warning
Cypache is currently under development and is NOT suitable for production, only for testing.
