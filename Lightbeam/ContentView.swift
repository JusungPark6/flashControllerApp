//
//  ContentView.swift
//  Lightbeam
//
//  Created by Jusung Park on 1/10/24.
//
import SwiftUI
import AVFoundation
import Photos
import UIKit

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    
    private let captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput = AVCapturePhotoOutput()
    private var movieFileOutput = AVCaptureMovieFileOutput()
    private var photoCaptureCompletionBlock: ((UIImage?) -> Void)?
    @Published var isCameraReady = false
    @Published var sessionMediaItems: [MediaItem] = []
    private var zoomDebounceTimer: Timer?
    private var currentCameraType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var isVideoModeEnabled = false
    @Published var isRecording = false
    
    override init() {
        super.init()
        DispatchQueue.main.async {
            self.checkPermissions()
            self.setupCaptureSession()
        }
    }
    
    private func checkPermissions() {
        // Check video permissions
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // If video authorized, proceed to check audio permissions
            checkAudioPermissions()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        // If video access granted, proceed to check audio permissions
                        self?.checkAudioPermissions()
                    }
                    // Handle the case when video access is not granted
                    // You may want to show an alert to the user or handle it accordingly
                }
            }
        default:
            // Handle the case when video access is denied or restricted
            // You may want to show an alert to the user or handle it accordingly
            break
        }
    }
    
    private func checkAudioPermissions() {
        // Check audio permissions
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCaptureSession()
                    }
                    // Handle the case when audio access is not granted
                    // You may want to show an alert to the user or handle it accordingly
                }
            }
        default:
            // Handle the case when audio access is denied or restricted
            // You may want to show an alert to the user or handle it accordingly
            break
        }
    }
    
    //    private func setupCaptureSession() {
    //        captureSession.beginConfiguration()
    //        captureSession.inputs.forEach { captureSession.removeInput($0) }
    //        captureSession.outputs.forEach { captureSession.removeOutput($0) }
    //        configureCameraInput()
    //
    //        if isVideoModeEnabled {
    //            // Setup for video mode
    //            if captureSession.canAddOutput(movieFileOutput) {
    //                captureSession.addOutput(movieFileOutput)
    //            }
    //        } else {
    //            // Setup for photo mode
    //            if captureSession.canAddOutput(photoOutput) {
    //                captureSession.addOutput(photoOutput)
    //            }
    //        }
    //
    //        captureSession.commitConfiguration()
    //        setupPreviewLayer()
    //        startRunning()
    //        DispatchQueue.main.async {
    //            self.isCameraReady = true
    //        }
    //    }
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        // Configure camera input
        configureCameraInput()
        
        // Add audio input if in video mode
        if isVideoModeEnabled {
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
        }
        
        // Configure outputs based on mode
        if isVideoModeEnabled {
            if captureSession.canAddOutput(movieFileOutput) {
                captureSession.addOutput(movieFileOutput)
            }
        } else {
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
        }
        
        captureSession.commitConfiguration()
        setupPreviewLayer()
        startRunning()
        
        DispatchQueue.main.async {
            self.isCameraReady = true
        }
    }
    
    
    private func configureCameraInput() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        self.videoDeviceInput = input
    }
    
    func setupPreviewLayer() {
        DispatchQueue.main.async {
            if self.previewLayer == nil {
                self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                self.previewLayer?.videoGravity = .resizeAspectFill
            }
        }
    }
    
    func startRunning() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopRunning() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func captureImage(completion: @escaping (UIImage?) -> Void) {
        guard self.captureSession.isRunning else {
            completion(nil)
            return
        }
        self.photoCaptureCompletionBlock = completion
        let settings = AVCapturePhotoSettings()
        self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoCaptureCompletionBlock?(nil)
            print("Error capturing photo: \(error.localizedDescription)")
        } else if let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) {
            photoCaptureCompletionBlock?(image)
        } else {
            photoCaptureCompletionBlock?(nil)
        }
    }
    func saveImageToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    if let error = error {
                        print("Error saving photo to library: \(error.localizedDescription)")
                    } else if success {
                        print("Photo saved to library")
                    }
                })
            } else {
                print("Photo library access not authorized")
            }
        }
    }
    
    func setTorchLevel(to level: Float) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch,
              !isUltraWideCameraActive() else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            if level <= 0.0 {
                device.torchMode = .off
            } else {
                let minTorchLevel: Float = 0.01
                let adjustedLevel = max(level, minTorchLevel)
                try device.setTorchModeOn(level: adjustedLevel)
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used: \(error.localizedDescription)")
        }
    }
    
    func fetchMostRecentPhoto(completion: @escaping (UIImage?, PHAsset?) -> Void) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let lastAsset = fetchResult.firstObject else {
            completion(nil, nil)
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        
        manager.requestImage(for: lastAsset, targetSize: CGSize(width: 200, height: 200), contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async {
                completion(image, lastAsset)
            }
        }
    }
    
    func addPreviewLayer(to view: UIView) {
        DispatchQueue.main.async {
            guard let previewLayer = self.previewLayer else { return }
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
        }
    }
    func captureAndSaveImage(completion: @escaping (UIImage?) -> Void) {
        captureImage { [weak self] capturedImage in
            guard let self = self, let image = capturedImage else {
                completion(nil)
                return
            }
            self.sessionMediaItems.append(.photo(image))
            self.saveImageToPhotos(image)
            completion(image) // Pass the image back to update the UI or further process
        }
    }
    
    func getMaxZoomFactor() -> CGFloat {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return 1.0 // Default value if the device cannot be accessed
        }
        
        return 10.0/*CGFloat(device.activeFormat.videoMaxZoomFactor)*/
    }
    
    func getMinZoomFactor() -> CGFloat {
        if let ultraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            return 0.5 // Ultra-wide lens typically supports 0.5x zoom
        } else {
            return 1.0 // Default zoom level for standard wide-angle camera
        }
    }
    
    func setZoomLevel(_ zoomLevel: CGFloat) {
        DispatchQueue.main.async {
            if zoomLevel < 1.0 && self.currentCameraType != .builtInUltraWideCamera {
                self.switchToUltraWideCamera()
            } else if zoomLevel >= 1.0 && self.currentCameraType != .builtInWideAngleCamera {
                self.switchToWideAngleCamera()
            }
            self.applyZoomLevel(zoomLevel)
        }
    }
    
    private func applyZoomLevel(_ zoomLevel: CGFloat) {
        guard let device = self.videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let newZoomFactor = (self.currentCameraType == .builtInUltraWideCamera) ? max(zoomLevel * 2, device.minAvailableVideoZoomFactor) : zoomLevel
            device.videoZoomFactor = min(newZoomFactor, device.activeFormat.videoMaxZoomFactor)
            device.unlockForConfiguration()
        } catch {
            print(error)
        }
    }
    
    func switchToUltraWideCamera() {
        guard currentCameraType != .builtInUltraWideCamera,
              let ultraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) else {
            return
        }
        currentCameraType = .builtInUltraWideCamera
        updateCameraInput(with: ultraWideCamera)
    }
    
    func switchToWideAngleCamera() {
        guard currentCameraType != .builtInWideAngleCamera,
              let wideAngleCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        currentCameraType = .builtInWideAngleCamera
        updateCameraInput(with: wideAngleCamera)
    }
    
    func updateCameraInput(with camera: AVCaptureDevice) {
        DispatchQueue.main.async {
            self.captureSession.beginConfiguration()
            if let currentInput = self.videoDeviceInput {
                self.captureSession.removeInput(currentInput)
            }
            
            if let input = try? AVCaptureDeviceInput(device: camera), self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
                self.videoDeviceInput = input
            }
            
            self.captureSession.commitConfiguration()
            self.setupPreviewLayer()
        }
    }
    
    func currentCameraSupportsFlash() -> Bool {
        return videoDeviceInput?.device.hasTorch ?? false
    }
    
    func isUltraWideCameraActive() -> Bool {
        return currentCameraType == .builtInUltraWideCamera
    }
    
    // Video functions
    // Toggle between photo and video mode
    func toggleVideoMode(_ enabled: Bool) {
        isVideoModeEnabled = enabled
        setupCaptureSession()
    }
    
    func isRecordingVideo() -> Bool {
        return movieFileOutput.isRecording
    }
    
    func startRecordingVideo() {
        guard !movieFileOutput.isRecording else { return }
        
        let outputFileURL = getVideoOutputURL()
        movieFileOutput.startRecording(to: outputFileURL, recordingDelegate: self)
        isRecording = true
    }
    
    func stopRecordingVideo() {
        guard movieFileOutput.isRecording else { return }
        movieFileOutput.stopRecording()
        isRecording = false
    }
    
    private func getVideoOutputURL() -> URL {
        let outputPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("tempMovie\(Date().timeIntervalSince1970).mov")
        return URL(fileURLWithPath: outputPath)
    }
    
    
    // Implement AVCaptureFileOutputRecordingDelegate methods
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error occurred while recording video: \(error.localizedDescription)")
            return
        }
        
        // Save the video to the photo library
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            // Generate thumbnail for the video
                            if let thumbnail = self.generateThumbnail(for: outputFileURL) {
                                self.sessionMediaItems.append(.video(outputFileURL, thumbnail)) // Save video URL and thumbnail
                            } else {
                                // Fallback in case thumbnail generation fails
                                self.sessionMediaItems.append(.video(outputFileURL, UIImage())) // Add video URL with an empty UIImage
                            }
                        } else {
                            print("Error saving video: \(error?.localizedDescription ?? "unknown error")")
                        }
                    }
                }
            } else {
                print("Photo library access not authorized")
            }
        }
    }
    
    func generateThumbnail(for url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        let time = CMTimeMakeWithSeconds(1.0, preferredTimescale: 600)
        do {
            let img = try assetImgGenerate.copyCGImage(at: time, actualTime: nil)
            let thumbnail = UIImage(cgImage: img)
            return thumbnail
        } catch {
            print("Error generating thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
    
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        cameraManager.addPreviewLayer(to: view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        cameraManager.addPreviewLayer(to: uiView)
    }


}

struct PhotoViewerController: UIViewControllerRepresentable {
    var mediaItems: [MediaItem]
    
    func makeUIViewController(context: Context) -> UIViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pageViewController.dataSource = context.coordinator
        
        // Determine the initial view controller based on the first media item
        if let firstMediaItem = mediaItems.first {
            let firstViewController = context.coordinator.viewController(for: firstMediaItem)
            pageViewController.setViewControllers(
                [firstViewController].compactMap { $0 },
                direction: .forward,
                animated: false
            )
        } else {
            // Handle empty mediaItems by setting a placeholder or an empty view controller
            let placeholderViewController = UIViewController()
            pageViewController.setViewControllers([placeholderViewController], direction: .forward, animated: false)
        }
        
        return pageViewController
    }
    
    func createViewController(for mediaItem: MediaItem?) -> UIViewController? {
        switch mediaItem {
        case .photo(let image):
            return PhotoViewController(image: image)
        case .video(let url, _): // Extract only the URL from the tuple
            return VideoViewController(videoURL: url)
        case .none:
            return nil
        }
    }
    

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(mediaItems: mediaItems)
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource {
        var mediaItems: [MediaItem]
        
        init(mediaItems: [MediaItem]) {
            self.mediaItems = mediaItems.reversed() // Reverse the order of media items
        }
        
        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController) -> UIViewController? {
                guard let index = indexOfViewController(viewController) else { return nil }
                if index > 0 {
                    // Return the previous media item's view controller
                    return self.viewController(for: mediaItems[index - 1])
                }
                return nil
            }
        
        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController) -> UIViewController? {
                guard let index = indexOfViewController(viewController) else { return nil }
                if index < mediaItems.count - 1 {
                    // Return the next media item's view controller
                    return self.viewController(for: mediaItems[index + 1])
                }
                return nil
            }
        
        // Returns the appropriate UIViewController for a given media item
        private func indexOfViewController(_ viewController: UIViewController) -> Int? {
            if let photoVC = viewController as? PhotoViewController {
                return mediaItems.firstIndex(where: {
                    if case .photo(let image) = $0, image == photoVC.image {
                        return true
                    }
                    return false
                })
            } else if let videoVC = viewController as? VideoViewController {
                return mediaItems.firstIndex(where: {
                    if case .video(let url, _) = $0, url == videoVC.videoURL {
                        return true
                    }
                    return false
                })
            }
            return nil
        }
        
        // Returns the appropriate UIViewController for a given media item
        func viewController(for mediaItem: MediaItem?) -> UIViewController? {
            switch mediaItem {
            case .photo(let image):
                return PhotoViewController(image: image)
            case .video(let url, _): // Extract only the URL from the tuple
                return VideoViewController(videoURL: url)
            case .none:
                return nil
            }
        }
    }
}

enum MediaItem {
    case photo(UIImage)
    case video(URL, UIImage)
}

class VideoViewController: UIViewController {
    var videoURL: URL
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    // Initialization with a video URL
    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Called after the controller's view is loaded into memory
    override func viewDidLoad() {
        super.viewDidLoad()
        setupPlayer()
    }

    // Sets up the AVPlayer and AVPlayerLayer to play the video
    private func setupPlayer() {
        // Create an AVPlayer with the video URL
        player = AVPlayer(url: videoURL)
        // Create an AVPlayerLayer and set it as the layer of the view
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = view.bounds
        playerLayer?.videoGravity = .resizeAspect // Maintain aspect ratio of the video
        if let playerLayer = self.playerLayer {
            view.layer.addSublayer(playerLayer)
        }
    }

    // Called when the view is about to made visible
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Start playing the video when the view appears
        player?.play()
    }

    // Called when the view is about to be removed from the view hierarchy
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pause the video when the view is about to disappear
        player?.pause()
    }

    // Ensures that the player layer resizes with the view
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }
}


class PhotoViewController: UIViewController {
    var imageView = UIImageView()
    var image: UIImage?

    init(image: UIImage?) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        imageView.image = image
        if image != nil {
            print("Image loaded in PhotoViewController")
        } else {
            print("No image to display in PhotoViewController")
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

struct ZoomControlView: View {
    @Binding var zoomLevel: CGFloat
    var minZoomLevel: CGFloat
    var maxZoomLevel: CGFloat
    @Binding var isZoomControlVisible: Bool
    
    @State private var totalRotation: Double = 0
    @State private var previousAngle: Angle?
    
    private var zoomIncrement: CGFloat {
        (maxZoomLevel - minZoomLevel) / 2400 // Adjust sensitivity
    }
    
    var body: some View {
        Group {
            if isZoomControlVisible {
                ZStack {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                        .frame(width: 120, height: 120)
                    
                    ForEach(0..<45, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 1, height: i % 2 == 0 ? 20 : 3)
                            .offset(y: i % 2 == 0 ? -60 : -55)
                            .rotationEffect(Angle(degrees: Double(i) * 8))
                    }
                    .mask(Circle().frame(width: 120, height: 120).scaleEffect(0.95))
                }
                .rotationEffect(Angle(degrees: totalRotation))
                .mask(partialCircleMask())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let center = CGPoint(x: 60, y: 60)
                            let currentAngle = angleBetweenPoints(center, value.location)
                            if let previousAngle = previousAngle {
                                let angleDelta = currentAngle - previousAngle
                                
                                let zoomChange = CGFloat(angleDelta.degrees) * zoomIncrement
                                let potentialNewZoomLevel = min(max(minZoomLevel, zoomLevel + zoomChange), maxZoomLevel)
                                
                                // Only apply the changes if the zoom level is not at its bounds
                                if potentialNewZoomLevel != zoomLevel && !(zoomLevel == minZoomLevel && zoomChange < 0) && !(zoomLevel == maxZoomLevel && zoomChange > 0) {
                                    totalRotation += angleDelta.degrees
                                    zoomLevel = potentialNewZoomLevel
                                }
                            }
                            previousAngle = currentAngle
                        }
                        .onEnded { _ in
                            previousAngle = nil
                        }
                )
            }
        }
    }
    
    private func angleBetweenPoints(_ center: CGPoint, _ point: CGPoint) -> Angle {
        let deltaX = point.x - center.x
        let deltaY = point.y - center.y
        return Angle(radians: atan2(deltaY, deltaX))
    }
    private func partialCircleMask() -> some View {
        GeometryReader { geometry in
            Path { path in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let radius = min(geometry.size.width, geometry.size.height) / 2
                path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(150), clockwise: false)
                path.addLine(to: center)
                path.closeSubpath()
            }
        }
    }
}




struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isCapturing = false
    @State private var showShutterFlash = false
    @State private var sliderValue: Double = 0
    @State private var recentPhoto: UIImage?
    @State private var recentAsset: PHAsset?
    @State private var isPhotoViewerPresented = false
    @State private var zoomLevel: CGFloat = 1.0
    @State private var isZoomControlVisible: Bool = false
    @State private var isRecordingVideo = false
    @State private var isVideoMode = false
    
    
    var body: some View {
        
        ZStack {
            CameraPreview(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    cameraManager.startRunning()
                    fetchLatestPhoto()
                }
                .onDisappear {
                    cameraManager.stopRunning()
                }
            
            if showShutterFlash {
                Color.black
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showShutterFlash = false
                        }
                    }
            }
            
            VStack {
                Spacer()
                Button(action: {
                    isVideoMode.toggle()
                    cameraManager.toggleVideoMode(isVideoMode)
                }) {
                    Text(isVideoMode ? "Camera" : "Video")
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.gray)
                        .cornerRadius(10)
                }
                .opacity(0.55)
                .padding(.bottom, 5)
                HStack {
                    Spacer()
                    
                    //Photo Preview
                    
                    if let recentMediaItem = cameraManager.sessionMediaItems.last {
                        Button(action: {
                            isPhotoViewerPresented = true
                        }) {
                            switch recentMediaItem {
                            case .photo(let image), .video(_, let image): // Use the image (thumbnail for videos)
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill() // Change to .scaledToFill() to cover the entire circle
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle()) // Clip to a circular shape
                            }
                        }
                        .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 3))
                        .padding(3)
                        .sheet(isPresented: $isPhotoViewerPresented) {
                            PhotoViewerController(mediaItems: cameraManager.sessionMediaItems)
                        }
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 50, height: 50)
                            .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 3))
                            .padding(3)
                    }
                    Spacer()
                    
                    //Shutter Button
                    Button(action: {
                        if isVideoMode {
                            if cameraManager.isRecordingVideo() {
                                cameraManager.stopRecordingVideo()
                                isRecordingVideo = false
                            } else {
                                cameraManager.startRecordingVideo()
                                isRecordingVideo = true
                            }
                        }
                        else {
                            cameraManager.captureAndSaveImage { capturedImage in
                                if let image = capturedImage {
                                    // Handle the captured image (e.g., update the UI or save it)
                                    recentPhoto = image
                                }
                            }
                            showShutterFlash = true
                        }
                        
                    }) { Group {
                        if isVideoMode && cameraManager.isRecording {
                            // Button appearance when recording video
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 40, height: 40)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(Circle())
                        } else {
                            // Button appearance when not recording or in photo mode
                            Image(systemName: isVideoMode ? "video.circle.fill" : "camera.circle")
                                .font(.system(size: 50))
                                .foregroundColor(isVideoMode ? .red : .blue)
                        }
                    }
                    .padding(10)
                    .background(isVideoMode ? Color.red : Color.black)
                    .clipShape(Circle())
                    .shadow(color: Color.white.opacity(0.3), radius: 5, x: 5, y: 5)
                    .shadow(color: Color.white.opacity(0.3), radius: 5, x: -5, y: -5)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    }
                    
                    //                    Spacer()
                    
                    //  Zoom button
                    
                    ZStack {
                        // ZoomControlView
                        ZoomControlView(
                            zoomLevel: $zoomLevel,
                            minZoomLevel: cameraManager.getMinZoomFactor(),
                            maxZoomLevel: cameraManager.getMaxZoomFactor(),
                            isZoomControlVisible: $isZoomControlVisible
                        )
                        .opacity(isZoomControlVisible ? 1 : 0)
                        
                        // Zoom Button
                        Button(action: {
                            isZoomControlVisible.toggle() // Toggle the visibility of the ZoomControlView
                        }) {
                            Text("\(zoomLevel, specifier: "%.1fx")")
                                .font(.system(size: 15))
                                .foregroundColor(Color.yellow)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .frame(width: 120, height: 120)
                    .padding(.trailing, -25)
                    
                    
                    Spacer()
                    
                    // Video toggle
//                    Button(action: {
//                        isVideoMode.toggle()
//                        cameraManager.toggleVideoMode(isVideoMode)
//                    }) {
//                        Text(isVideoMode ? "Camera" : "Video")
//                            .foregroundColor(.gray)
//                            .padding(5)
//                            .background(Color.white)
//                            .cornerRadius(10)
//                    }
//                    .padding(.bottom, 10)
                    
                }
            }.onAppear {
                print("Session media items count: \(cameraManager.sessionMediaItems.count)")
            }.onChange(of: zoomLevel) { newZoomLevel in
                cameraManager.setZoomLevel(newZoomLevel)
            }
            VStack {
                if !cameraManager.isUltraWideCameraActive() {
                    Slider(value: $sliderValue, in: 0...1)
                        .rotationEffect(.degrees(-90))
                        .opacity(0.5)
                        .frame(width: 300, height: 50)
                        .padding()
                        .onChange(of: sliderValue) { newValue in
                            cameraManager.setTorchLevel(to: Float(newValue))
                        }
                        .position(x: UIScreen.main.bounds.width - 30, y: UIScreen.main.bounds.height / 2)
                }
            }
        }
        .onAppear {
            fetchLatestPhoto()
        }
    }
    
    private func fetchLatestPhoto() {
        cameraManager.fetchMostRecentPhoto { fetchedImage, asset in
            recentPhoto = fetchedImage
            recentAsset = asset
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
            ContentView()
    }
}

