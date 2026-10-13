import AVFoundation
import UIKit
import VisionKit

/// Scans one food barcode with the camera and hands back its digits. VisionKit's live scanner does the recognising;
/// the screen is Baseline's own: a dark frame with a cut-out, a moving scan line, the torch and "Type the number".
@MainActor
final class BarcodeScanner: NSObject, DataScannerViewControllerDelegate {
    enum Outcome { case code(String), cancelled, denied, unavailable, manual }

    private var done: ((Outcome) -> Void)?
    private weak var scanner: DataScannerViewController?
    private weak var host: ScanHost?
    private var overlay: ScanOverlay?

    func scan(from view: UIView, completion: @escaping (Outcome) -> Void) {
        guard done == nil else { completion(.cancelled); return }
        // the live scanner needs an iPhone XS or newer, and never runs in the simulator
        guard DataScannerViewController.isSupported else { completion(.unavailable); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            present(from: view, completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in ok ? self.present(from: view, completion) : completion(.denied) }
            }
        default:
            completion(.denied)
        }
    }

    private func present(from view: UIView, _ completion: @escaping (Outcome) -> Void) {
        guard DataScannerViewController.isAvailable, var top = view.window?.rootViewController else { completion(.unavailable); return }
        while let p = top.presentedViewController { top = p }
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: true, isPinchToZoomEnabled: true,
                                                isGuidanceEnabled: false, isHighlightingEnabled: false)
        scanner.delegate = self
        let overlay = ScanOverlay(frame: view.bounds)
        overlay.onClose = { [weak self] in self?.finish(.cancelled) }
        overlay.onManual = { [weak self] in self?.finish(.manual) }
        // only codes inside the frame count
        overlay.onFrame = { [weak scanner] rect in scanner?.regionOfInterest = rect }
        // our own screen around the scanner: VisionKit's overlay container doesn't take taps, so the buttons sit above it
        let host = ScanHost(scanner: scanner, overlay: overlay)
        host.onClose = { [weak self] in self?.finish(.cancelled) }
        self.scanner = scanner
        self.host = host
        self.overlay = overlay
        done = completion
        top.present(host, animated: true) {
            do { try scanner.startScanning() } catch { self.finish(.unavailable) }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        guard done != nil, overlay?.isFound == false else { return }
        for item in addedItems {
            if case .barcode(let code) = item, let digits = code.payloadStringValue, !digits.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                overlay?.showFound()
                // a short beat on the green frame, so it's clear what happened
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self.finish(.code(digits))
                }
                return
            }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        finish(.unavailable)
    }

    private func finish(_ outcome: Outcome) {
        guard let done else { return }
        self.done = nil
        overlay?.setTorch(false)
        scanner?.stopScanning()
        host?.dismiss(animated: true)
        scanner = nil
        host = nil
        overlay = nil
        done(outcome)
    }
}

/// Full screen: the live scanner, the overlay above it (its buttons take taps; everywhere else touches go through to the
/// scanner for pinch to zoom), and a swipe down or the accessibility escape gesture to close.
final class ScanHost: UIViewController {
    private let scanner: DataScannerViewController
    private let overlay: ScanOverlay
    var onClose: (() -> Void)?

    init(scanner: DataScannerViewController, overlay: ScanOverlay) {
        self.scanner = scanner
        self.overlay = overlay
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        swipe.direction = .down
        view.addGestureRecognizer(swipe)
    }

    @objc private func swipedDown() { onClose?() }

    override func accessibilityPerformEscape() -> Bool { onClose?(); return true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

/// The scanner's screen: everything but the frame dimmed, rounded corner marks, a scan line, a title,
/// a close button, the torch and "Type the number".
final class ScanOverlay: UIView {
    var onClose: (() -> Void)?
    var onManual: (() -> Void)?
    var onFrame: ((CGRect) -> Void)?
    private(set) var isFound = false

    private let dim = CAShapeLayer()
    private let corners = CAShapeLayer()
    private let line = CAGradientLayer()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .system)
    private let manualButton = UIButton(type: .system)
    private var torchOn = false
    private var lastFrame = CGRect.zero

    private static let green = UIColor(red: 0.18, green: 0.66, blue: 0.40, alpha: 1)
    private static let accent = UIColor(red: 0.23, green: 0.55, blue: 0.92, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        dim.fillRule = .evenOdd
        dim.fillColor = UIColor.black.withAlphaComponent(0.58).cgColor
        layer.addSublayer(dim)

        corners.strokeColor = UIColor.white.cgColor
        corners.fillColor = UIColor.clear.cgColor
        corners.lineWidth = 4
        corners.lineCap = .round
        layer.addSublayer(corners)

        line.colors = [Self.accent.withAlphaComponent(0).cgColor, Self.accent.cgColor, Self.accent.withAlphaComponent(0).cgColor]
        line.startPoint = CGPoint(x: 0, y: 0.5)
        line.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(line)

        titleLabel.text = "Scan a barcode"
        titleLabel.font = Self.rounded(22, .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        hintLabel.text = "Hold the barcode inside the frame. Swipe down to close."
        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        addSubview(titleLabel)
        addSubview(hintLabel)

        style(closeButton, symbol: "xmark", label: "Close")
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        style(torchButton, symbol: "flashlight.off.fill", label: "Torch")
        torchButton.addAction(UIAction { [weak self] _ in self?.toggleTorch() }, for: .touchUpInside)
        torchButton.isHidden = !(AVCaptureDevice.default(for: .video)?.hasTorch ?? false)
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Type the number"
        cfg.image = UIImage(systemName: "keyboard")
        cfg.imagePadding = 8
        cfg.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 20, bottom: 13, trailing: 20)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var b = a
            b.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            return b
        }
        manualButton.configuration = cfg
        manualButton.addAction(UIAction { [weak self] _ in self?.onManual?() }, for: .touchUpInside)
        addSubview(closeButton)
        addSubview(torchButton)
        addSubview(manualButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Only the buttons take touches; the rest goes through to the scanner underneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    private static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }

    /// A round glass button with an SF Symbol.
    private func style(_ b: UIButton, symbol: String, label: String) {
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        cfg.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        b.configuration = cfg
        b.accessibilityLabel = label
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaInsets
        let w = min(bounds.width - 64, 320), hgt = (w * 0.6).rounded()
        let box = CGRect(x: (bounds.width - w) / 2, y: max(safe.top + 150, bounds.height * 0.40 - hgt / 2), width: w, height: hgt)

        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(roundedRect: box, cornerRadius: 22))
        dim.frame = bounds
        dim.path = path.cgPath
        corners.frame = bounds
        corners.path = Self.cornerMarks(box, radius: 22, length: 30).cgPath

        line.frame = CGRect(x: box.minX + 16, y: box.minY + 12, width: box.width - 32, height: 2)
        if line.animation(forKey: "scan") == nil && !isFound {
            let a = CABasicAnimation(keyPath: "position.y")
            a.fromValue = box.minY + 14
            a.toValue = box.maxY - 14
            a.duration = 1.6
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            line.add(a, forKey: "scan")
        }

        closeButton.frame = CGRect(x: 16, y: safe.top + 8, width: 44, height: 44)
        titleLabel.frame = CGRect(x: 24, y: box.minY - 92, width: bounds.width - 48, height: 30)
        hintLabel.frame = CGRect(x: 32, y: box.minY - 58, width: bounds.width - 64, height: 40)
        let bottom = bounds.height - safe.bottom - 28
        let mw = manualButton.intrinsicContentSize.width
        manualButton.frame = CGRect(x: (bounds.width - mw) / 2, y: bottom - 50, width: mw, height: 50)
        torchButton.frame = CGRect(x: (bounds.width - 56) / 2, y: box.maxY + 36, width: 56, height: 56)

        if box != lastFrame { lastFrame = box; onFrame?(box) }
    }

    /// Four rounded corners around the frame, like a camera's focus marks.
    private static func cornerMarks(_ r: CGRect, radius: CGFloat, length: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        // top left
        p.move(to: CGPoint(x: r.minX, y: r.minY + length))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(withCenter: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX + length, y: r.minY))
        // top right
        p.move(to: CGPoint(x: r.maxX - length, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(withCenter: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .pi * 1.5, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + length))
        // bottom right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - length))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(withCenter: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX - length, y: r.maxY))
        // bottom left
        p.move(to: CGPoint(x: r.minX + length, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(withCenter: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - length))
        return p
    }

    /// The frame turns green and gives a small pulse when a code is read.
    func showFound() {
        isFound = true
        line.removeAllAnimations()
        line.isHidden = true
        corners.strokeColor = Self.green.cgColor
        let pulse = CABasicAnimation(keyPath: "lineWidth")
        pulse.fromValue = 4
        pulse.toValue = 7
        pulse.duration = 0.18
        pulse.autoreverses = true
        corners.add(pulse, forKey: "pulse")
        titleLabel.text = "Got it"
        hintLabel.text = "Looking it up…"
    }

    private func toggleTorch() { setTorch(!torchOn) }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, on != torchOn || !on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
            var cfg = torchButton.configuration
            cfg?.image = UIImage(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            cfg?.baseBackgroundColor = on ? UIColor.white.withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.16)
            cfg?.baseForegroundColor = on ? .black : .white
            torchButton.configuration = cfg
        } catch {}
    }
}
