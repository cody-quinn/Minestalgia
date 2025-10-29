# Minestalgia

Minestalgia is a reimplementation of the Minecraft Beta 1.7.3 server software. It's written in Zig and as of now doesn't depend on any third party libraries, or even libc. It makes use of Linux's asynchronous I/O APIs for networking, and for now runs entirely on a single thread.

The project is still in its infancy and under very active development.

Note: If running yourself please use Debug or ReleaseSafe build modes. ReleaseFast is currently broken.
