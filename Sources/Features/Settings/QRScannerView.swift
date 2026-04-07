import AVFoundation
import SwiftUI

/// 二维码扫描视图，使用 AVCaptureSession 实时识别 QR 码
/// 扫描成功后通过 onScanned 回调返回解码文本
struct QRScannerView: UIViewControllerRepresentable {

    /// 扫描成功回调
    let onScanned: (String) -> Void
    /// 关闭扫描器
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScanned = onScanned
        controller.onDismiss = onDismiss
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

// MARK: - 扫描控制器

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScanned: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// 防止重复触发回调
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    // MARK: - 相机设置

    private func setupCamera() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showNoCameraAlert()
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            showNoCameraAlert()
            return
        }

        guard captureSession.canAddInput(videoInput) else {
            showNoCameraAlert()
            return
        }
        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            showNoCameraAlert()
            return
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        // 预览图层
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        // 添加扫描框指示
        addScanOverlay()

        // 关闭按钮
        addCloseButton()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned else { return }

        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            return
        }

        // 震动反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        hasScanned = true
        captureSession.stopRunning()
        onScanned?(stringValue)
    }

    // MARK: - UI 辅助

    /// 扫描框覆盖层
    private func addScanOverlay() {
        let overlayView = ScanOverlayView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 提示文字
        let label = UILabel()
        label.text = "将二维码对准框内"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
        ])
    }

    /// 关闭按钮
    private func addCloseButton() {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        button.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func closeTapped() {
        captureSession.stopRunning()
        onDismiss?()
    }

    /// 无相机时提示
    private func showNoCameraAlert() {
        let label = UILabel()
        label.text = "无法访问相机\n请在设置中允许使用相机"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

// MARK: - 扫描框覆盖层

/// 半透明遮罩，中间留出扫描窗口
private final class ScanOverlayView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let scanSize: CGFloat = min(rect.width, rect.height) * 0.65
        let scanRect = CGRect(
            x: (rect.width - scanSize) / 2,
            y: (rect.height - scanSize) / 2,
            width: scanSize,
            height: scanSize
        )

        // 半透明背景
        context.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
        context.fill(rect)

        // 扫描区域透明
        context.clear(scanRect)

        // 四角装饰线
        let cornerLength: CGFloat = 24
        let lineWidth: CGFloat = 3
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // 左上
            (CGPoint(x: scanRect.minX, y: scanRect.minY + cornerLength),
             CGPoint(x: scanRect.minX, y: scanRect.minY),
             CGPoint(x: scanRect.minX + cornerLength, y: scanRect.minY)),
            // 右上
            (CGPoint(x: scanRect.maxX - cornerLength, y: scanRect.minY),
             CGPoint(x: scanRect.maxX, y: scanRect.minY),
             CGPoint(x: scanRect.maxX, y: scanRect.minY + cornerLength)),
            // 左下
            (CGPoint(x: scanRect.minX, y: scanRect.maxY - cornerLength),
             CGPoint(x: scanRect.minX, y: scanRect.maxY),
             CGPoint(x: scanRect.minX + cornerLength, y: scanRect.maxY)),
            // 右下
            (CGPoint(x: scanRect.maxX - cornerLength, y: scanRect.maxY),
             CGPoint(x: scanRect.maxX, y: scanRect.maxY),
             CGPoint(x: scanRect.maxX, y: scanRect.maxY - cornerLength)),
        ]

        for (start, corner, end) in corners {
            context.move(to: start)
            context.addLine(to: corner)
            context.addLine(to: end)
        }
        context.strokePath()
    }
}
