//
//  ARViewController.swift
//  iphone_rbg_depth
//
//  ARKit View Controller for recording RGB and LiDAR depth videos
//

import UIKit
import ARKit
import AVFoundation
import CoreMedia
import Network

class ARViewController: UIViewController, ARSessionDelegate {

    // MARK: - Properties
    var arSession: ARSession!
    var rgbImageView: UIImageView!
    var depthImageView: UIImageView!
    var statusLabel: UILabel!
    var lidarStatusLabel: UILabel!
    var fpsLabel: UILabel!
    var recordButton: UIButton!
    var recordingStatusLabel: UILabel!
    var streamButton: UIButton!
    var streamStatusLabel: UILabel!

    private var frameCount = 0
    private var lastFPSUpdate = Date()
    private var isProcessingFrame = false
    private var lastFrameTime = Date()
    private let targetFrameInterval: TimeInterval = 1.0 / 30.0  // Process at 30 FPS

    // Recording components
    private var videoRecorder: VideoRecorder?
    private var isRecording = false

    // Streaming components
    private var tcpStreamer = TCPFrameStreamer()
    private var isStreaming = false
    private var streamConnected = false
    private var rgbStreamFrameNumber: UInt32 = 0
    private var depthStreamFrameNumber: UInt32 = 0
    private var lastStreamFrameTime = Date.distantPast
    private let streamFrameInterval: TimeInterval = 1.0 / 12.0
    private let streamJPEGQuality: CGFloat = 0.45
    private let streamDepthFrameStride: UInt32 = 2
    private let streamHostDefaultsKey = "streamServerHost"
    private let streamPortDefaultsKey = "streamServerPort"
    private let defaultStreamHost = "172.20.10.2"  // Typical host IP over iPhone USB tethering
    private let defaultStreamPort = 8888

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupAR()
        checkLiDARAvailability()
        setupStreamer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arSession.pause()

        // Stop recording if active
        if isRecording {
            stopRecording()
        }

        if isStreaming {
            stopStreaming()
        }
    }

    // MARK: - UI Setup

    func setupUI() {
        view.backgroundColor = .black

        // Create side-by-side image views
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        rgbImageView = UIImageView()
        rgbImageView.contentMode = .scaleAspectFit
        rgbImageView.backgroundColor = .darkGray
        stackView.addArrangedSubview(rgbImageView)

        depthImageView = UIImageView()
        depthImageView.contentMode = .scaleAspectFit
        depthImageView.backgroundColor = .darkGray
        stackView.addArrangedSubview(depthImageView)

        // Status label
        statusLabel = UILabel()
        statusLabel.text = "Initializing..."
        statusLabel.textColor = .white
        statusLabel.textAlignment = .left
        statusLabel.numberOfLines = 0
        statusLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // LiDAR status
        lidarStatusLabel = UILabel()
        lidarStatusLabel.textColor = .green
        lidarStatusLabel.textAlignment = .left
        lidarStatusLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        lidarStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lidarStatusLabel)

        // FPS label
        fpsLabel = UILabel()
        fpsLabel.text = "FPS: 0.0"
        fpsLabel.textColor = .yellow
        fpsLabel.textAlignment = .left
        fpsLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fpsLabel)

        // Streaming status label
        streamStatusLabel = UILabel()
        streamStatusLabel.text = "Network: Off"
        streamStatusLabel.textColor = .orange
        streamStatusLabel.textAlignment = .right
        streamStatusLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        streamStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(streamStatusLabel)

        // Recording status label
        recordingStatusLabel = UILabel()
        recordingStatusLabel.text = "Ready to record"
        recordingStatusLabel.textColor = .cyan
        recordingStatusLabel.textAlignment = .center
        recordingStatusLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        recordingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordingStatusLabel)

        // Record button
        recordButton = UIButton(type: .system)
        recordButton.setTitle("⏺ START RECORDING", for: .normal)
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.backgroundColor = .red
        recordButton.layer.cornerRadius = 25
        recordButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordButton)

        // Stream button
        streamButton = UIButton(type: .system)
        streamButton.setTitle("📡 START STREAMING", for: .normal)
        streamButton.setTitleColor(.white, for: .normal)
        streamButton.backgroundColor = .systemBlue
        streamButton.layer.cornerRadius = 18
        streamButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        streamButton.addTarget(self, action: #selector(streamButtonTapped), for: .touchUpInside)
        streamButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(streamButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: streamButton.leadingAnchor, constant: -8),

            lidarStatusLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 5),
            lidarStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),

            fpsLabel.topAnchor.constraint(equalTo: lidarStatusLabel.bottomAnchor, constant: 5),
            fpsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),

            streamButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            streamButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            streamButton.widthAnchor.constraint(equalToConstant: 180),
            streamButton.heightAnchor.constraint(equalToConstant: 36),

            streamStatusLabel.topAnchor.constraint(equalTo: streamButton.bottomAnchor, constant: 4),
            streamStatusLabel.trailingAnchor.constraint(equalTo: streamButton.trailingAnchor),
            streamStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: fpsLabel.trailingAnchor, constant: 8),

            recordingStatusLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -10),
            recordingStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 250),
            recordButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    // MARK: - AR Setup

    func setupAR() {
        arSession = ARSession()
        arSession.delegate = self

        let configuration = ARWorldTrackingConfiguration()

        // Enable scene depth if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        // Use the smallest 30 FPS format to lower encode/network load and latency.
        let availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        let formats30fps = availableFormats.filter { $0.framesPerSecond == 30 }
        if let lowLatencyFormat = formats30fps.min(by: {
            ($0.imageResolution.width * $0.imageResolution.height)
                < ($1.imageResolution.width * $1.imageResolution.height)
        }) {
            configuration.videoFormat = lowLatencyFormat
            let width = Int(lowLatencyFormat.imageResolution.width)
            let height = Int(lowLatencyFormat.imageResolution.height)
            print("✓ Using 30 FPS low-latency format: \(width)x\(height)")
        }

        arSession.run(configuration)
        print("✓ AR Session started")
    }

    func checkLiDARAvailability() {
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            lidarStatusLabel.text = "✓ LiDAR Supported"
            lidarStatusLabel.textColor = .green
            print("✓ LiDAR is supported on this device")
        } else {
            lidarStatusLabel.text = "✗ LiDAR Not Available"
            lidarStatusLabel.textColor = .red
            print("✗ LiDAR is not supported on this device")
        }
    }

    // MARK: - Recording Control

    @objc func recordButtonTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        videoRecorder = VideoRecorder()

        // Get dimensions from AR session
        let rgbWidth = 1920
        let rgbHeight = 1440
        let depthWidth = 256
        let depthHeight = 192
        let fps = 30

        do {
            try videoRecorder?.startRecording(
                rgbWidth: rgbWidth,
                rgbHeight: rgbHeight,
                depthWidth: depthWidth,
                depthHeight: depthHeight,
                fps: fps
            )

            isRecording = true

            // Update UI
            recordButton.setTitle("⏹ STOP RECORDING", for: .normal)
            recordButton.backgroundColor = .systemGray
            recordingStatusLabel.text = "Recording..."
            recordingStatusLabel.textColor = .red

            print("🎬 Recording started")

        } catch {
            print("❌ Failed to start recording: \(error.localizedDescription)")
            recordingStatusLabel.text = "Error: \(error.localizedDescription)"
            recordingStatusLabel.textColor = .red
        }
    }

    func stopRecording() {
        guard let recorder = videoRecorder else { return }

        isRecording = false

        // Update UI
        recordButton.setTitle("⏺ START RECORDING", for: .normal)
        recordButton.backgroundColor = .red
        recordButton.isEnabled = false
        recordingStatusLabel.text = "Saving..."
        recordingStatusLabel.textColor = .yellow

        recorder.stopRecording { [weak self] rgbURL, depthURL, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.recordingStatusLabel.text = "Error: \(error.localizedDescription)"
                    self.recordingStatusLabel.textColor = .red
                    self.recordButton.isEnabled = true
                }
                return
            }

            guard let rgbURL = rgbURL, let depthURL = depthURL else {
                DispatchQueue.main.async {
                    self.recordingStatusLabel.text = "Recording failed"
                    self.recordingStatusLabel.textColor = .red
                    self.recordButton.isEnabled = true
                }
                return
            }

            // Save to Photos
            VideoRecorder.saveToPhotos(rgbURL: rgbURL, depthURL: depthURL) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.recordingStatusLabel.text = "✅ Saved to Photos!"
                        self.recordingStatusLabel.textColor = .green
                    } else {
                        self.recordingStatusLabel.text = "Error saving: \(error?.localizedDescription ?? "unknown")"
                        self.recordingStatusLabel.textColor = .red
                    }

                    self.recordButton.isEnabled = true

                    // Reset status after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.recordingStatusLabel.text = "Ready to record"
                        self.recordingStatusLabel.textColor = .cyan
                    }
                }
            }
        }

        videoRecorder = nil
    }

    // MARK: - Streaming Control

    func setupStreamer() {
        tcpStreamer.onStatusChanged = { [weak self] statusText, connected in
            DispatchQueue.main.async {
                self?.streamConnected = connected
                self?.streamStatusLabel.text = statusText
                self?.streamStatusLabel.textColor = connected ? .green : .orange
            }
        }
    }

    @objc func streamButtonTapped() {
        if isStreaming {
            stopStreaming()
        } else {
            showStreamingConfigPrompt()
        }
    }

    func showStreamingConfigPrompt() {
        let savedHost = UserDefaults.standard.string(forKey: streamHostDefaultsKey) ?? defaultStreamHost
        let savedPort = UserDefaults.standard.integer(forKey: streamPortDefaultsKey)
        let port = savedPort > 0 ? savedPort : defaultStreamPort

        let alert = UIAlertController(
            title: "Start Streaming",
            message: "Tip: over USB tethering, your computer/Pi is often 172.20.10.2",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "Server IP"
            textField.text = savedHost
            textField.keyboardType = .numbersAndPunctuation
        }

        alert.addTextField { textField in
            textField.placeholder = "Port"
            textField.text = "\(port)"
            textField.keyboardType = .numberPad
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Start", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let host = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let portText = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !host.isEmpty, let portInt = Int(portText), (1...65535).contains(portInt) else {
                self.streamStatusLabel.text = "Network: Invalid host/port"
                self.streamStatusLabel.textColor = .red
                return
            }

            UserDefaults.standard.set(host, forKey: self.streamHostDefaultsKey)
            UserDefaults.standard.set(portInt, forKey: self.streamPortDefaultsKey)
            self.startStreaming(host: host, port: UInt16(portInt))
        })

        present(alert, animated: true)
    }

    func startStreaming(host: String, port: UInt16) {
        let metadata = buildSessionMetadata()

        isStreaming = true
        streamConnected = false
        rgbStreamFrameNumber = 0
        depthStreamFrameNumber = 0
        lastStreamFrameTime = Date.distantPast

        streamButton.setTitle("🛑 STOP STREAMING", for: .normal)
        streamButton.backgroundColor = .systemGray
        streamStatusLabel.text = "Network: Connecting..."
        streamStatusLabel.textColor = .orange

        tcpStreamer.connect(host: host, port: port, metadata: metadata)
    }

    func stopStreaming() {
        isStreaming = false
        streamConnected = false
        tcpStreamer.disconnect()

        streamButton.setTitle("📡 START STREAMING", for: .normal)
        streamButton.backgroundColor = .systemBlue
        streamStatusLabel.text = "Network: Off"
        streamStatusLabel.textColor = .orange
    }

    func buildSessionMetadata() -> [String: Any] {
        var rgbWidth = 1920
        var rgbHeight = 1440
        var depthWidth = 256
        var depthHeight = 192

        if let currentFrame = arSession.currentFrame {
            let rgbBuffer = currentFrame.capturedImage
            rgbWidth = CVPixelBufferGetWidth(rgbBuffer)
            rgbHeight = CVPixelBufferGetHeight(rgbBuffer)

            if let depthBuffer = currentFrame.sceneDepth?.depthMap {
                depthWidth = CVPixelBufferGetWidth(depthBuffer)
                depthHeight = CVPixelBufferGetHeight(depthBuffer)
            }
        }

        return [
            "sessionId": UUID().uuidString,
            "rgbWidth": rgbWidth,
            "rgbHeight": rgbHeight,
            "depthWidth": depthWidth,
            "depthHeight": depthHeight,
            "fps": Int(1.0 / streamFrameInterval),
            "depthStride": Int(streamDepthFrameStride),
            "rgbBitrate": 0,
            "rgbEncoding": "jpeg",
            "depthEncoding": "jpeg"
        ]
    }

    func sendStreamFrames(rgbImage: UIImage?, depthPixelBuffer: CVPixelBuffer?, timestampSeconds: TimeInterval) {
        guard isStreaming, streamConnected else { return }

        var didSendRGB = false
        if let rgbData = rgbImage?.jpegData(compressionQuality: streamJPEGQuality) {
            rgbStreamFrameNumber &+= 1
            tcpStreamer.sendFrame(
                type: .rgb,
                timestamp: timestampSeconds,
                frameNumber: rgbStreamFrameNumber,
                payload: rgbData,
                isKeyFrame: true
            )
            didSendRGB = true
        }

        let shouldSendDepth = didSendRGB && (rgbStreamFrameNumber % streamDepthFrameStride == 0)
        if shouldSendDepth,
           let depthBuffer = depthPixelBuffer,
           let depthData = DepthCompressor.compress(depthBuffer, format: .jpeg) {
            depthStreamFrameNumber &+= 1
            tcpStreamer.sendFrame(
                type: .depth,
                timestamp: timestampSeconds,
                frameNumber: depthStreamFrameNumber,
                payload: depthData,
                isKeyFrame: false
            )
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateFPS()

        // Throttle frame processing
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= targetFrameInterval else { return }
        guard !isProcessingFrame else { return }

        isProcessingFrame = true
        lastFrameTime = now

        // Get buffers
        let rgbPixelBuffer = frame.capturedImage
        let depthPixelBuffer = frame.sceneDepth?.depthMap
        let timestamp = CMTime(seconds: frame.timestamp, preferredTimescale: 600)

        // Write frames if recording
        if isRecording {
            videoRecorder?.writeRGBFrame(rgbPixelBuffer, timestamp: timestamp)

            if let depthBuffer = depthPixelBuffer {
                videoRecorder?.writeDepthFrame(depthBuffer, timestamp: timestamp)
            }

            // Update recording status
            if let frameCount = videoRecorder?.getFrameCount() {
                DispatchQueue.main.async {
                    self.recordingStatusLabel.text = "Recording... \(frameCount) frames"
                }
            }
        }

        let shouldSendStreamFrame = isStreaming && now.timeIntervalSince(lastStreamFrameTime) >= streamFrameInterval
        if shouldSendStreamFrame {
            lastStreamFrameTime = now
        }

        // Process on background queue for visualization
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                self?.isProcessingFrame = false
                return
            }

            // Convert images for display
            let rgbImage = DepthImageConverter.convertRGBToImage(rgbPixelBuffer)
            var depthImage: UIImage?

            if let depthBuffer = depthPixelBuffer {
                depthImage = DepthImageConverter.convertDepthToImage(depthBuffer)
            }

            if shouldSendStreamFrame {
                self.sendStreamFrames(
                    rgbImage: rgbImage,
                    depthPixelBuffer: depthPixelBuffer,
                    timestampSeconds: frame.timestamp
                )
            }

            // Update UI on main thread
            DispatchQueue.main.async {
                autoreleasepool {
                    self.rgbImageView.image = rgbImage
                    self.depthImageView.image = depthImage

                    // Log on first successful frame only
                    if self.frameCount == 1 {
                        if let rgbWidth = rgbImage?.size.width, let rgbHeight = rgbImage?.size.height {
                            print("\n=== Frame Data ===")
                            print("RGB: \(Int(rgbWidth))x\(Int(rgbHeight))")

                            if let depthImage = depthImage {
                                print("Depth: \(Int(depthImage.size.width))x\(Int(depthImage.size.height))")
                            }

                            print("Processing at ~30 FPS")
                            print("==================\n")
                        }
                    }

                    self.isProcessingFrame = false
                }
            }
        }
    }

    func updateFPS() {
        frameCount += 1

        let elapsed = Date().timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            DispatchQueue.main.async {
                self.fpsLabel.text = String(format: "FPS: %.1f", fps)
            }

            frameCount = 0
            lastFPSUpdate = Date()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ AR Session failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.statusLabel.text = "AR Error: \(error.localizedDescription)"
            self.statusLabel.textColor = .red
        }
    }
}

private enum StreamFrameType: UInt8 {
    case rgb = 0x01
    case depth = 0x02
    case metadata = 0x03
}

private final class TCPFrameStreamer {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "TCPFrameStreamerQueue")
    private var pendingMetadata: [String: Any]?
    private(set) var isConnected = false
    private var inFlightSendCount = 0
    private let maxInFlightSendCount = 2

    var onStatusChanged: ((String, Bool) -> Void)?

    func connect(host: String, port: UInt16, metadata: [String: Any]) {
        queue.async {
            self.disconnectLocked(shouldEmitStatus: false)
            self.pendingMetadata = metadata

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                self.emitStatus("Network: Invalid port", false)
                return
            }

            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
            self.connection = connection

            connection.stateUpdateHandler = { [weak self] state in
                self?.handleState(state)
            }

            self.emitStatus("Network: Connecting...", false)
            connection.start(queue: self.queue)
        }
    }

    func disconnect() {
        queue.async {
            self.disconnectLocked(shouldEmitStatus: true)
        }
    }

    func sendFrame(type: StreamFrameType, timestamp: TimeInterval, frameNumber: UInt32, payload: Data, isKeyFrame: Bool) {
        queue.async {
            guard self.isConnected else { return }
            self.sendPacket(
                type: type,
                timestamp: timestamp,
                frameNumber: frameNumber,
                payload: payload,
                isKeyFrame: isKeyFrame,
                enforceInflightLimit: true
            )
        }
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
            inFlightSendCount = 0
            emitStatus("Network: Connected ✓", true)
            sendPendingMetadata()

        case .failed(let error):
            isConnected = false
            emitStatus("Network error: \(error.localizedDescription)", false)
            disconnectLocked(shouldEmitStatus: false)

        case .cancelled:
            isConnected = false

        default:
            break
        }
    }

    private func sendPendingMetadata() {
        guard let metadata = pendingMetadata else { return }
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata, options: []) else {
            emitStatus("Network: Metadata encode failed", false)
            return
        }

        sendPacket(
            type: .metadata,
            timestamp: Date().timeIntervalSince1970,
            frameNumber: 0,
            payload: metadataData,
            isKeyFrame: false,
            enforceInflightLimit: false
        )

        pendingMetadata = nil
    }

    private func sendPacket(
        type: StreamFrameType,
        timestamp: TimeInterval,
        frameNumber: UInt32,
        payload: Data,
        isKeyFrame: Bool,
        enforceInflightLimit: Bool
    ) {
        guard let connection = connection else { return }
        if enforceInflightLimit && inFlightSendCount >= maxInFlightSendCount {
            return
        }

        var packet = Data(capacity: 18 + payload.count)

        var frameType = type.rawValue
        var timestampBits = timestamp.bitPattern.littleEndian
        var frameNumberLE = frameNumber.littleEndian
        var payloadSizeLE = UInt32(payload.count).littleEndian
        var keyFlag: UInt8 = isKeyFrame ? 1 : 0

        withUnsafeBytes(of: &frameType) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &timestampBits) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &frameNumberLE) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &payloadSizeLE) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &keyFlag) { packet.append(contentsOf: $0) }
        packet.append(payload)

        inFlightSendCount += 1
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                self.inFlightSendCount = max(0, self.inFlightSendCount - 1)
                if let error = error {
                    self.isConnected = false
                    self.emitStatus("Network send error: \(error.localizedDescription)", false)
                }
            }
        })
    }

    private func disconnectLocked(shouldEmitStatus: Bool) {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        pendingMetadata = nil
        isConnected = false
        inFlightSendCount = 0

        if shouldEmitStatus {
            emitStatus("Network: Off", false)
        }
    }

    private func emitStatus(_ text: String, _ connected: Bool) {
        onStatusChanged?(text, connected)
    }
}
