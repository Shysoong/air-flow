[![Join the chat at https://gitter.im/h2oai/h2o-flow](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/h2oai/h2o-flow?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

# AIR Flow

*AIR Flow* 是一个基于web的交互式计算环境，您可以在其中组合代码执行、文本、数学、图表和富媒体来构建机器学习工作流。

可以将Flow视为是一个拥有异步的、可重写可脚本化记录和重放能力的探索性数据分析和机器学习的混合了[GUI](https://en.wikipedia.org/wiki/Graphical_user_interface) + 
[REPL](https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop) + 故事看板的环境。
Flow通过静态分析和树重写来沙盒化并且在浏览器上运行用户端Javascript。
Flow是用CoffeeScript编写的，有一堆真正的嵌入式
[DSL](https://en.wikipedia.org/wiki/Domain-specific_language)s，用于响应性
[dataflow programming](https://en.wikipedia.org/wiki/Dataflow_programming), 标记生成、延迟评估和多播信号/插槽。

## 文档

在[h2o-3](https://github.com/h2oai/h2o-3)代码库中又一个关于*AIR Flow*很好的用户指南[user guide](https://github.com/h2oai/h2o-3/blob/8858aac90dce771f9025b16948b675f92b542715/h2o-docs/src/product/flow/README.md) 。

## 开发环境配置

强烈推荐您 clone [h2o-3](https://github.com/h2oai/h2o-3) 和 air-flow 在同一个目录中。 

如果你还没有，按照这些说明为[h2o-3](https://github.com/h2oai/h2o-3)开发[set up your preferred IDE environment](https://github.com/h2oai/h2o-3#47-setting-up-your-preferred-ide-environment) 。
    
1. 首先构建 H2O-3  `cd h2o-3 && ./gradlew build -x test` (在 h2o-E 目录下)

2. 为h2o-flow安装npm依赖 `npm i` (在 h2o-flow 目录下)

### 使用浏览器自动实时刷新开发

1. 以关闭跨域资源共享检查的方式启动H2O-3 `java -Dsys.ai.h2o.disable.cors=true -jar build/h2o.jar` (在 h2o-3 目录下)

2. 启动 webpack dev-server `npm run start` (在 h2o-flow 目录下)

这将打开一个带有自动刷新开发服务器的浏览器窗口。


### h2o-3 实例中开发

1. 运行 `make` 命令。这将复制构建资源到紧邻的h2o-3目录中。

2. 在IDE中不运行gradle启动h2o-3 （这会覆盖本地flow构建）

### Testing a new Flow Feature with Sparkling Water  

Flow can also be used with [Sparkling Water](https://github.com/h2oai/sparkling-water)  
Follow this guide develop and test new Sparkling Water features in Flow.  
adapted from the comments on this PR https://github.com/h2oai/h2o-flow/pull/13  

##### copy built js files from one place to another  
in the `h2o-3` directory run:  
`cp h2o-web/src/main/resources/www/flow/js/* h2o-web/lib/h2o-flow/build/js/`  

##### 构建 h2o-3  
在 `h2o-3` 目录下运行：
`./gradlew publishToMavenLocal -x test`  

##### 构建 sparkling water  
在 `sparkling-water` 目录下运行：
`./gradlew clean build -x test -x integTest`  

##### 打开 Sparkling Water Shell  
在 `sparkling-water` 目录下运行：
`bin/sparkling-shell`  

在sparkling water shell 中 
在 `scala>` 提示符下运行： 
`import org.apache.spark.h2o._`  
`H2OContext.getOrCreate(sc)`  

现在可以在sparkling water shell 中用指定的IP地址打开Flow

现在可以在Flow中测试您的更改来
