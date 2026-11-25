# FishRadar 的单目距离与靠近检测

资料核对日期为 2026 年 11 月 24 日。以下性能数据来自模型发布方，FishRadar 的效果和开销仍待实测。

本文保留 v0.2.0 的基线记录和深度模型调研。v0.2.1 的发布实现、对照日志与回放方法见 [距离判断与诊断](distance-geometry-plan.md)。

先用现有人员框建立可复现的基线，把「已经很近」和「正在靠近」分开评估。再按需验证 Apple 的 Depth Anything V2 Small Core ML 版本，看看相对深度能否减少远处横穿、姿态变化和遮挡引起的误报。如果产品需要固定距离分档，再验证能输出米数的 Depth Anything V2 Metric Hypersim Small。运行时沿用普通 RGB 摄像头，无需用户调整坐姿、角度或做现场标定。

## 靠近趋势与当前距离

- **靠近趋势**取决于同一目标随时间的变化。现有 `VNDetectHumanRectanglesRequest` 取上半身框，`ApproachTracker` 根据框高度持续增长给出黄、红提示。普通情况下检测间隔为 0.4 秒，近期有提示时为 0.2 秒。人在近处横向路过、转身或被遮挡时，框也可能变大。可以先在同一轨迹上比较平滑后的框高变化率，检查框是否触边、中心是否突然跳动，并把横移幅度作为辅助信号。斜向走近也会横移，不能单凭横移否决。见 [摄像头处理](../Sources/main.swift)、[靠近跟踪](../Sources/ApproachTracker.swift)。
- **当前距离**回答人员出现时是否已经很近。若可见物体大小保持稳定且相机设置固定，针孔近似下图像高度 `h ≈ fH/Z`，其中 `f` 为像素焦距，`H` 为对象可见的实际高度，`Z` 为轴向深度。上半身框的 `H` 会随目标、姿态和裁切变化，只适合给出粗略的近处线索。米制模型用图像和训练先验估计尺度，其误差仍需在办公室与目标摄像头上测量。若要按相机直线距离划档，要先确认模型对深度的定义，画面边缘的轴向深度与直线距离有差异。见 [Depth Pro 2 输出定义](https://github.com/apple-aiml-research/ml-depth-pro-2#interpreting-the-depth)。

早期跟踪器回放了三组合成检测框。每组输入三帧，间隔 0.4 秒，宽度为 0.14。固定横坐标、框高从 0.16 增至 0.215 时得到绿、绿、黄。固定大框横向移动，或者一入画就是大框并保持静止，三帧均为绿色。这组回放表明当时的提示依赖框的增长。现用版本也会根据多帧确认的大框提示近处横穿或直接入画。

## 模型与部署条件

| 方案 | 原始输出与成本 | 适合的验证 |
| --- | --- | --- |
| Apple Core ML 的 **Depth Anything V2 Small** | 24.8M 参数。Apple 提供 49.8 MB F16 及 19 MB F16P6 两种包。Apple 的 F16 测试中，M1 Max 为 32.80 ms，M3 Max 为 24.58 ms，主要计算单元为 Neural Engine。Small 权重和 Apple 模型卡标注 Apache-2.0。 | 首选拿现成 F16 做对照，再比较 F16P6 的结果和实际成本。同帧可以比较人员与背景远近。输出是尺度与偏移均不确定的相对逆深度，跨帧需运行验证或用稳定背景对齐，统一的分数阈值不能代表固定米数。见 [Apple 模型列表](https://developer.apple.com/machine-learning/models/)、[Apple 模型卡](https://huggingface.co/apple/coreml-depth-anything-v2-small/blob/main/README.md)、[V2 论文](https://proceedings.neurips.cc/paper_files/paper/2024/file/26cfdcd8fe6fd75cc53e92963a656c58-Paper-Conference.pdf)。 |
| **Depth Anything V2 Metric Hypersim Small** | 24.8M 参数，官方室内模型输出米数，权重标注 Apache-2.0，官方推理示例为 PyTorch。 | 先用上游权重在本地验证距离和近处入画，再决定是否用 `coremltools` 转换并比对 PyTorch 与 Core ML 的误差。Apple 上一行的相对深度模型包与耗时不能沿用。见 [上游米制版本](https://github.com/DepthAnything/Depth-Anything-V2/tree/main/metric_depth)、[Hypersim Small 模型卡](https://huggingface.co/depth-anything/Depth-Anything-V2-Metric-Hypersim-Small)。 |
| Apple **Depth Pro 2 S** | Apple 于 2026 年 11 月发布，提供官方 Core ML 包与 macOS 15 及以上的 Apple Silicon 实时摄像头示例。S 的四帧窗口在 640×360 和 854×480 上分别为 13 ms 和 26 ms，均为 M4 Max GPU 的模型推理中位数，不含预处理和渲染。示例在 854×480 时约需 1.5 GB 内存。Core ML 模型输出需要像素焦距才能换算为米，官方另有视场估计模型。 | 仅作科研参考。权重协议将用途限于非商业科研和学术开发，并明确排除产品开发。见 [Apple 研究页](https://machinelearning.apple.com/research/depth-pro-2-monocular)、[Mac 示例与实测](https://github.com/apple-aiml-research/ml-depth-pro-2/blob/main/demo/README.md)、[权重许可](https://github.com/apple-aiml-research/ml-depth-pro-2/blob/main/LICENSE_MODEL)。 |

Apple Vision 也能估计人体相对相机的 3D 位置。其 3D 姿态请求只返回最显著的一人，缺少足够深度元数据时，体高采用 1.8 米参考值。这个接口值得在单人画面下做对照，但有多人的办公室可能只返回使用者。`AVCaptureDepthDataOutput` 则依赖设备和视频格式支持深度数据，可在兼容硬件上另行评估。见 [Vision 3D 人体姿态](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images)、[AVFoundation 深度输出](https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput)。

## 试验顺序

1. **先测人员框基线。** 用相同的带时间戳检测序列回放现有规则和候选规则，记录每次被识别为使用者、被区域过滤、轨迹丢失和首次黄／红的时刻。保留横向路过与斜向接近样本，分别比较误报与漏报。现有规则会排除盖住画面中心且足够大的最大框，近处入画时也要测这个条件是否排错人。见 [现有使用者过滤](../Sources/main.swift)。
2. **按需运行相对深度。** 只在首次发现其他人员、几何信号分歧或接近阈值时对全帧推理，试验上限设为每秒 2.5 次，同一时刻只保留一个推理任务，忙时跳过旧帧。把同一时间戳的人员框按深度输入的缩放、裁切和坐标原点映射，取每个上身框中心的小片区域中位数，降低边界和背景像素的干扰。镜像只用于显示。可从多个固定背景区域取深度分布稳定的参考点，检验对齐后人员深度趋势是否可靠。背景参考移位或被挡、人员框截断或时间戳过期时，把深度记为未知并沿用几何结果。见 [Vision 坐标系](https://developer.apple.com/documentation/vision/boundingboxproviding/boundingbox)、[缩放与裁切选项](https://developer.apple.com/documentation/vision/vnimagecropandscaleoption)。
3. **需要固定距离时再做米制原型。** 用软尺测开发用的距离点，按相同的视角和躯干取样规则记录真值，并在多台摄像头上检验统一阈值。测试场地的距离标记仅用于评分，最终用户无需标定。米制原型成功后，再决定近处入画和持续靠近是否需要独立的提示。原型阶段把模型输出保留在本地内存或只记录数值，观察模式关闭自动切换和诊断照片，避免实验判定触发真实动作。见 [现有设置及诊断选项](../README.md#设置)。

## 验证标准

用开发者自己的摄像头或可控素材，在本地测静止、正向接近、斜向接近、远／近横穿、近处直接入画、后退、转身弯腰、贴边、短暂遮挡、两人交错和光线变化。独自测试时，把自己的走位作为目标，在隔离的离线回放中暂时跳过使用者排除，或使用获准的合成素材。另用默认规则回放有使用者和路人的样本，单独计算使用者误过滤造成的漏报。每个场景至少重复 10 次，用不同场景实例调参和验收。

| 指标 | 首轮建议门槛 |
| --- | --- |
| 靠近识别 | 正向和斜向接近的召回率至少 90%。统计从首次进入应提醒状态到首次黄／红的时间，P95 以 1 秒为目标。 |
| 误报和近处入画 | 横穿、转身、静止与遮挡分别报告触发黄／红的次数和测试总次数。采用深度方案前，合计误报相对几何基线至少下降 30%，接近召回率下降不超过 5 个百分点。近处直接入画和近处横穿分别统计当前距离分档及靠近判定。 |
| 米制误差 | 在约 1、2、3、5 米的开发测试点记录绝对误差中位数、P90 和各摄像头的偏差。仅当跨摄像头的近／远分档准确率至少 90%、且分档边界附近的 P90 绝对误差不超过相邻档位间距的一半时，再评估在正式提示中使用固定距离。 |
| 后台资源 | 在目标 Apple Silicon 机器上用相同摄像头、场景和检测频率分别跑基线、`.all` 和 `.cpuAndNeuralEngine`，每组至少连续 20 分钟。记录预处理及推理的 P50／P95、进程 CPU、常驻内存、摄像头丢帧和系统热状态。首轮试验以进程 CPU 平均增加不超过 2 个百分点、常驻内存 P95 不超过 200 MiB、摄像头接收帧率下降不超过基线的 5% 为建议门槛。另在视频通话共享摄像头时复测。见 [Core ML 性能分析](https://developer.apple.com/documentation/coreml/analyzing-a-core-ml-model-s-performance-in-xcode)、[FishRadar 实验监控](../README.md#实验监控与隐私)。 |
