//
//  MetalPreviewRenderer.swift
//  TwinSnap
//
//  MTKView に CIImage を aspectFill で描画する。前後カメラで CIContext を共有する。
//

#if canImport(UIKit)
import CoreImage
import MetalKit
import UIKit

final class MetalPreviewRenderer: NSObject {

    let mtkView: MTKView

    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    /// SampleBufferDelegate から更新される直近フレーム。
    private var currentImage: CIImage?
    private let imageLock = NSLock()

    /// MTLDevice / CIContext / CommandQueue は前後で共有。
    private struct SharedResources {
        let device: MTLDevice
        let ciContext: CIContext
        let commandQueue: MTLCommandQueue
    }

    private static let shared: SharedResources? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        let context = CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        return SharedResources(device: device, ciContext: context, commandQueue: queue)
    }()

    static func makeShared() -> MetalPreviewRenderer? {
        guard let resources = shared else { return nil }
        return MetalPreviewRenderer(resources: resources)
    }

    /// VideoAssetWriter など他のコンポーネントで CIContext を再利用するためのアクセサ。
    static var sharedCIContext: CIContext? {
        shared?.ciContext
    }

    private init(resources: SharedResources) {
        self.ciContext = resources.ciContext
        self.commandQueue = resources.commandQueue
        self.mtkView = MTKView(frame: .zero, device: resources.device)
        self.mtkView.framebufferOnly = false
        self.mtkView.enableSetNeedsDisplay = false
        self.mtkView.isPaused = true
        self.mtkView.colorPixelFormat = .bgra8Unorm
        self.mtkView.autoResizeDrawable = true
        super.init()
        self.mtkView.delegate = self
    }

    /// 新しいフレームを描画キューに投入。SampleBufferDelegate のバックグラウンドキューからも安全。
    func present(_ image: CIImage) {
        imageLock.lock()
        currentImage = image
        imageLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.mtkView.draw()
        }
    }
}

extension MetalPreviewRenderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        imageLock.lock()
        let image = currentImage
        imageLock.unlock()

        guard let image,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let drawableSize = view.drawableSize
        let sourceExtent = image.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0,
              drawableSize.width > 0, drawableSize.height > 0 else {
            return
        }

        // aspectFill: 両dim が drawable を満たす最小スケール
        let scale = max(
            drawableSize.width / sourceExtent.width,
            drawableSize.height / sourceExtent.height
        )
        let scaledWidth = sourceExtent.width * scale
        let scaledHeight = sourceExtent.height * scale
        let offsetX = (drawableSize.width - scaledWidth) / 2
        let offsetY = (drawableSize.height - scaledHeight) / 2

        // 画像原点 (0,0) を drawable 内の (offsetX, offsetY) に置くよう translate → scale
        let transform = CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
        let displayImage = image.transformed(by: transform)

        let renderBounds = CGRect(origin: .zero, size: drawableSize)
        ciContext.render(
            displayImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: renderBounds,
            colorSpace: colorSpace
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

#endif
