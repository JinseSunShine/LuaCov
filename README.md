# LuaCov lua函数覆盖和执行时间

git 地址： https://github.com/JinseSunShine/LuaCov.git

#### 介绍

**1. 统计函数的调用次数**

> 统计每个函数的调用频率，优化频繁调用的函数

**2. 统计每个函数的执行时间**

> 统计从函数调入到函数调出所执行的时间



### 实现原理

1. 通过 sethook 注册监控函数， 监控'call' 和’return'事件。函数调出时刻与调入时刻的差值即函数的执行时间

2. debug.getinfo 获取函数的执行环境，对统计信息进行记录

    1. debug.getinfo  原生方法是当前最耗时的地方，因此将此部分移到了C中实现

3. 离线导出项目所有的lua函数

    1. 获取当前的堆栈信息和执行环境，因为lua对尾调用方法做过优化，可能会取不到函数名称，因此离线导出项目中所有的函数，通过文件的行号来确定对应执行的函数名

        

### 文件详解

* **runner.lua 	 启动和统计，打印部分**
* **hook.lua   用 lua 实现的hook 接口**
* **defaults.lua  配置部分**
* **LuaCovMonitor.cpp 用C实现的hook**
* **LuaCovExport.lua 离线导出所有的lua函数**
* **LuaCovRecordFunc.lua 导出的所有lua函数**

