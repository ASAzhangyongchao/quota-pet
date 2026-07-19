import AppKit
import QuartzCore

@MainActor
final class PetGlowContainerView: NSView {
    let petView: PetAppKitView
    private let ambientLayer = CALayer()
    private let accentLayer = CALayer()
    private var style: QuotaVisualStyle

    var shadowLayersHaveExplicitPaths: Bool {
        ambientLayer.shadowPath != nil && accentLayer.shadowPath != nil
    }

    init(petView: PetAppKitView, style: QuotaVisualStyle) {
        self.petView = petView
        self.style = style
        super.init(frame: NSRect(origin: .zero, size: FloatingPetPanelContract.default.size))
        wantsLayer = true
        layer?.masksToBounds = false
        configureShadowLayers()
        addSubview(petView)
        layoutSubtreeIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(style: QuotaVisualStyle) {
        guard self.style != style else { return }
        self.style = style
        applyStyle()
    }

    override func layout() {
        super.layout()
        petView.frame = NSRect(
            origin: CGPoint(x: FloatingPetPanelContract.glowInset, y: FloatingPetPanelContract.glowInset),
            size: FloatingPetPanelContract.visiblePetSize
        )
        updateShadowPaths(
            CGPath(
                ellipseIn: petView.frame.insetBy(dx: 4, dy: 4),
                transform: nil
            )
        )
    }

    private func configureShadowLayers() {
        guard let rootLayer = layer else { return }
        [ambientLayer, accentLayer].forEach {
            $0.frame = bounds
            $0.masksToBounds = false
            rootLayer.addSublayer($0)
        }
        ambientLayer.shadowColor = NSColor.black.cgColor
        ambientLayer.shadowOpacity = 0.22
        ambientLayer.shadowRadius = 5
        ambientLayer.shadowOffset = CGSize(width: 0, height: -1)
        accentLayer.shadowRadius = 7
        accentLayer.shadowOffset = .zero
        applyStyle()
    }

    private func applyStyle() {
        withoutImplicitLayerAnimations {
            accentLayer.shadowColor = style.haloKind.nsColor.cgColor
            accentLayer.shadowOpacity = Float(style.haloOpacity)
        }
    }

    private func updateShadowPaths(_ path: CGPath) {
        withoutImplicitLayerAnimations {
            ambientLayer.frame = bounds
            accentLayer.frame = bounds
            ambientLayer.shadowPath = path
            accentLayer.shadowPath = path
        }
    }
}

@MainActor
final class DetailGlowContainerView: NSView {
    let hostedView: NSView
    let materialView = NSVisualEffectView()
    private let ambientLayer = CALayer()
    private let accentLayer = CALayer()
    private var style: QuotaVisualStyle

    var shadowLayersHaveExplicitPaths: Bool {
        ambientLayer.shadowPath != nil && accentLayer.shadowPath != nil
    }

    init(hostedView: NSView, style: QuotaVisualStyle) {
        self.hostedView = hostedView
        self.style = style
        super.init(frame: NSRect(origin: .zero, size: FloatingPetPanelContract.expandedSize))
        wantsLayer = true
        layer?.masksToBounds = false
        configureShadowLayers()
        configureMaterialView()
        layoutSubtreeIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(style: QuotaVisualStyle) {
        applyAccessibilityAppearance()
        guard self.style != style else { return }
        self.style = style
        applyStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAccessibilityAppearance()
    }

    override func layout() {
        super.layout()
        materialView.frame = NSRect(
            origin: CGPoint(x: FloatingPetPanelContract.glowInset, y: FloatingPetPanelContract.glowInset),
            size: FloatingPetPanelContract.detailContentSize
        )
        let path = CGPath(
            roundedRect: materialView.frame,
            cornerWidth: 22,
            cornerHeight: 22,
            transform: nil
        )
        withoutImplicitLayerAnimations {
            ambientLayer.frame = bounds
            accentLayer.frame = bounds
            ambientLayer.shadowPath = path
            accentLayer.shadowPath = path
        }
    }

    private func configureShadowLayers() {
        guard let rootLayer = layer else { return }
        [ambientLayer, accentLayer].forEach {
            $0.frame = bounds
            $0.masksToBounds = false
            rootLayer.addSublayer($0)
        }
        ambientLayer.shadowColor = NSColor.black.cgColor
        ambientLayer.shadowOpacity = 0.30
        ambientLayer.shadowRadius = 7
        ambientLayer.shadowOffset = CGSize(width: 0, height: -2)
        accentLayer.shadowRadius = 8
        accentLayer.shadowOffset = .zero
        applyStyle()
    }

    private func configureMaterialView() {
        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 22
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.borderWidth = 1
        materialView.layer?.masksToBounds = true
        addSubview(materialView)

        hostedView.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: materialView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),
        ])
        applyAccessibilityAppearance()
    }

    private func applyStyle() {
        withoutImplicitLayerAnimations {
            accentLayer.shadowColor = style.haloKind.nsColor.cgColor
            accentLayer.shadowOpacity = Float(style.haloOpacity * 0.80)
        }
    }

    private func applyAccessibilityAppearance() {
        let workspace = NSWorkspace.shared
        if workspace.accessibilityDisplayShouldReduceTransparency {
            materialView.material = .windowBackground
        } else {
            materialView.material = .hudWindow
        }
        let strongContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        withoutImplicitLayerAnimations {
            materialView.layer?.borderWidth = strongContrast ? 1.5 : 1
            materialView.layer?.borderColor = NSColor.labelColor
                .withAlphaComponent(strongContrast ? 0.42 : 0.20)
                .cgColor
        }
    }
}

private func withoutImplicitLayerAnimations(_ update: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    update()
    CATransaction.commit()
}

private extension QuotaHaloKind {
    var nsColor: NSColor {
        switch self {
        case .ready:
            NSColor(deviceRed: 0.12, green: 0.90, blue: 0.76, alpha: 1)
        case .warning:
            NSColor(deviceRed: 1.00, green: 0.65, blue: 0.18, alpha: 1)
        case .depleted:
            NSColor(deviceRed: 1.00, green: 0.28, blue: 0.24, alpha: 1)
        case .unavailable:
            NSColor(deviceRed: 0.43, green: 0.58, blue: 0.72, alpha: 1)
        }
    }
}
