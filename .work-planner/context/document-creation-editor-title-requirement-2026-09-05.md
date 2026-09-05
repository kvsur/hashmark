# Document creation and editor title requirement

Captured: 2026-09-05

## User requirement (verbatim)

现在在首页的目录页或者子目录新增文件的时候，仅仅就要求输入文件名，输入完成之后建立了一个空的文件，这个交互很拉胯；

更好的交互应该是点击之后就直接跳转到 editor 页面去了，在这里创建一个新的；

但是editor页面现在也有个问题，不能看到文件名，不能编辑文件名；也不是很合理；

如果名称输入框不输入 就使用现有的 命名兜底逻辑；

## Follow-up decision (verbatim)

创建时机：进入前立即创建（推荐）
