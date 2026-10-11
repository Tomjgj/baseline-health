import AVFoundation
import UIKit
import VisionKit

/// Scans one food barcode with the camera (VisionKit's live scanner) and hands back its digits.
@MainActor
final class BarcodeScanner: NSObject, DataScannerViewControllerDelegate {
    enum Outcome { case code(String), cancelled, denied, unavailable }

    private var done: ((Outcome) -> Void)?
    private var nav: UINavigationController?

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
                                                isHighFrameRateTrackingEnabled: false, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = self
        scanner.navigationItem.title = "Scan a barcode"
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.finish(.cancelled) })
        let nav = UINavigationController(rootViewController: scanner)
        nav.modalPresentationStyle = .fullScreen
        nav.overrideUserInterfaceStyle = .dark
        self.nav = nav
        done = completion
        top.present(nav, animated: true) {
            do { try scanner.startScanning() } catch { self.finish(.unavailable) }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        for item in addedItems {
            if case .barcode(let code) = item, let digits = code.payloadStringValue, !digits.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                finish(.code(digits))
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
        (nav?.viewControllers.first as? DataScannerViewController)?.stopScanning()
        nav?.dismiss(animated: true)
        nav = nil
        done(outcome)
    }
}
