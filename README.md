vnodebypass
=====================

### An expermental tool to hide jailbreak files for bypass detection.



- https://gitlab.com/alias20/vnodebypass/-/tree/rootless

- 修复了原代码中全局变量放在h头文件中

Each symbol should only be defined once; that is, it should only be defined in one m file. By putting the definition in a header file, it gets defined in each m file that includes that header.

Define it in one of your m files (whichever is most relevant), and change what you have in the header to a declaration (using the extern keyword).

The definition makes space for the data; the declaration simply tells the compiler that there is a definition somewhere else. So every m file that uses the constant needs to have a declaration, but only one m file should have the definition.

- How to build
```bash
make clean
make package FINALPACKAGE=1
```