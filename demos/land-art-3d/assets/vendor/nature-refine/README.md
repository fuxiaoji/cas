# 圆冠自然树选样

本轮运行使用 Quaternius **Ultimate Nature Pack** 的 CommonTree 1/3/5 三款圆冠树，原作者 CC0 许可。原官方来源：<https://quaternius.com/packs/ultimatenature.html>；公开 GLB 转换镜像：<https://github.com/trebeljahr/quaternius-showcase/tree/main/public/glb/nature_pack>。原作者与包名对照见同级旧包 `../quaternius-free/LICENSES.md`。

旧瘦长桦树与层叠伞状松树不再作为本模块默认。三款树保持原模型轴、法线与多表面结构，按整体AABB等比例归一，根部落在渲染地面。山坡坡度过高、建筑/道路周围拒绝随机生成，不通过拉长树干适配高差。96米块 MultiMesh 共享几何和材质；近景行道树约7.1米，森林约10.5米，另有有限尺度变化。

此轮也从原作者 itch.io 免费入口尝试 Stylized Nature MegaKit Standard：公开99MB包支持分段，但后续图像范围反复403，未取得完整依赖，未作为运行资产。已取消整包下载并移除不完整大包；保留研究记录和不完整源在 `source/`，由 `.gdignore` 隔离，避免未完成 glTF 进入 Godot 导入。没有使用付费 Pro/Source 内容、Tripo 或账户。
