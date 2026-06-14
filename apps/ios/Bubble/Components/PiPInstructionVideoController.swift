import AVFoundation
import AVKit
import SwiftUI
import UIKit

final class PiPInstructionVideoController: NSObject, AVPictureInPictureControllerDelegate {
    private let player = AVPlayer()
    private weak var playerLayer: AVPlayerLayer?
    private var pictureInPictureController: AVPictureInPictureController?
    private var onStarted: (() -> Void)?
    private var onFailed: ((String) -> Void)?
    private var startAttempts = 0
    private var didReportStartResult = false
    private var endObserver: NSObjectProtocol?

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func attach(playerLayer: AVPlayerLayer) {
        self.playerLayer = playerLayer
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect

        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if pictureInPictureController == nil || pictureInPictureController?.playerLayer !== playerLayer {
            guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
                return
            }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            if #available(iOS 14.2, *) {
                controller.requiresLinearPlayback = true
            }
            pictureInPictureController = controller
        }
    }

    func start(onStarted: @escaping () -> Void, onFailed: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            self.onStarted = onStarted
            self.onFailed = onFailed
            self.didReportStartResult = false
            self.startAttempts = 0

            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                self.failStart("Picture in Picture is not available on this device.")
                return
            }

            guard self.pictureInPictureController != nil else {
                self.failStart("Picture in Picture is still preparing. Try again in a moment.")
                return
            }

            guard let videoURL = Bundle.main.url(forResource: "Frame-2", withExtension: "mov") else {
                self.failStart("The instructional video is missing from this build.")
                return
            }

            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                self.failStart("Nima could not prepare video playback.")
                return
            }

            let item = AVPlayerItem(url: videoURL)
            self.installLoopObserver(for: item)
            self.player.replaceCurrentItem(with: item)
            self.player.play()
            self.attemptStartPictureInPicture()
        }
    }

    func stop() {
        DispatchQueue.main.async {
            if self.pictureInPictureController?.isPictureInPictureActive == true {
                self.pictureInPictureController?.stopPictureInPicture()
            }
            self.player.pause()
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard !didReportStartResult else { return }
        didReportStartResult = true
        onStarted?()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        failStart(error.localizedDescription)
    }

    private func installLoopObserver(for item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
    }

    private func attemptStartPictureInPicture() {
        guard let controller = pictureInPictureController else {
            failStart("Picture in Picture is still preparing. Try again in a moment.")
            return
        }

        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            return
        }

        startAttempts += 1
        guard startAttempts <= 10 else {
            failStart("Picture in Picture is not ready yet. Try again in a moment.")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.attemptStartPictureInPicture()
        }
    }

    private func failStart(_ message: String) {
        guard !didReportStartResult else { return }
        didReportStartResult = true
        player.pause()
        onFailed?(message)
    }
}

struct PiPInstructionVideoHost: UIViewRepresentable {
    let controller: PiPInstructionVideoController

    func makeUIView(context: Context) -> PiPInstructionPlayerView {
        let view = PiPInstructionPlayerView()
        controller.attach(playerLayer: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PiPInstructionPlayerView, context: Context) {
        controller.attach(playerLayer: uiView.playerLayer)
    }
}

final class PiPInstructionPlayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
