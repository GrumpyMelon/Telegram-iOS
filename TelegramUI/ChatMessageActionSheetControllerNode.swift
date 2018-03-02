import Foundation
import Display
import AsyncDisplayKit

private let shadowInset: CGFloat = 8.0

private func generateShadowImage(theme: PresentationTheme) -> UIImage? {
    return generateImage(CGSize(width: 32.0 + shadowInset * 2.0, height: 32.0 + shadowInset * 2.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setShadow(offset: CGSize(width: 0.0, height: 0.0), blur: 20.0, color: UIColor(white: 0.0, alpha: 0.2).cgColor)
        context.setFillColor(theme.actionSheet.opaqueItemBackgroundColor.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: shadowInset, y: shadowInset), size: CGSize(width: size.width - shadowInset * 2.0, height: size.height - shadowInset * 2.0)))
    })?.stretchableImage(withLeftCapWidth: 16 + Int(shadowInset) / 2, topCapHeight: 16 + Int(shadowInset) / 2)
}

private final class MessageActionButtonNode: HighlightableButtonNode {
    let theme: PresentationTheme
    let separatorNode: ASDisplayNode
    let backgroundNode: ASDisplayNode
    
    init(theme: PresentationTheme) {
        self.theme = theme
        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true
        self.separatorNode.backgroundColor = theme.actionSheet.opaqueItemSeparatorColor
        
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.alpha = 0.0
        self.backgroundNode.backgroundColor = theme.actionSheet.opaqueItemHighlightedBackgroundColor
        
        super.init()
        
        self.setAttributedTitle(NSAttributedString(string: " "), for: [])
        
        self.insertSubnode(self.separatorNode, at: 0)
        self.insertSubnode(self.backgroundNode, at: 1)
        
        self.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    if let supernode = strongSelf.titleNode.supernode {
                        strongSelf.titleNode.removeFromSupernode()
                        supernode.addSubnode(strongSelf.titleNode)
                    }
                    strongSelf.backgroundNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backgroundNode.alpha = 1.0
                } else {
                    strongSelf.backgroundNode.alpha = 0.0
                    strongSelf.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25)
                }
            }
        }
    }
    
    override func layout() {
        super.layout()
        self.separatorNode.frame = CGRect(origin: CGPoint(x: 0.0, y: self.bounds.size.height - UIScreenPixel), size: CGSize(width: self.bounds.size.width, height: UIScreenPixel))
        self.backgroundNode.frame = self.bounds
    }
}

final class ChatMessageActionSheetControllerNode: ViewControllerTracingNode {
    private let theme: PresentationTheme
    
    private let inputDimNode: ASDisplayNode
    private let itemsShadowNode: ASImageNode
    private let itemsContainerNode: ASDisplayNode
    
    private let actions: [ChatMessageContextMenuSheetAction]
    private let dismissed: () -> Void
    private let actionNodes: [MessageActionButtonNode]
    
    private let feedback = HapticFeedback()
    private var validLayout: ContainerViewLayout?
    
    init(theme: PresentationTheme, actions: [ChatMessageContextMenuSheetAction], dismissed: @escaping () -> Void) {
        self.theme = theme
        self.actions = actions
        self.dismissed = dismissed
        
        self.inputDimNode = ASDisplayNode()
        self.inputDimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        
        self.itemsShadowNode = ASImageNode()
        self.itemsShadowNode.isLayerBacked = true
        self.itemsShadowNode.displayWithoutProcessing = true
        self.itemsShadowNode.displaysAsynchronously = false
        self.itemsShadowNode.image = generateShadowImage(theme: theme)
        
        self.itemsContainerNode = ASDisplayNode()
        self.itemsContainerNode.backgroundColor = theme.actionSheet.opaqueItemBackgroundColor
        self.itemsContainerNode.cornerRadius = 16.0
        self.itemsContainerNode.clipsToBounds = true
        
        self.actionNodes = actions.map { action in
            let node = MessageActionButtonNode(theme: theme)
            node.setAttributedTitle(NSAttributedString(string: action.title, font: Font.regular(20.0), textColor: action.color == .destructive ? theme.actionSheet.destructiveActionTextColor : theme.actionSheet.controlAccentColor), for: [])
            return node
        }
        
        super.init()
        
        self.addSubnode(self.inputDimNode)
        self.addSubnode(self.itemsShadowNode)
        self.addSubnode(self.itemsContainerNode)
        
        for actionNode in actionNodes {
            self.itemsContainerNode.addSubnode(actionNode)
            actionNode.addTarget(self, action: #selector(actionPressed(_:)), forControlEvents: .touchUpInside)
        }
        
        self.feedback.prepareImpact()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.inputDimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTap(_:))))
    }
    
    func animateIn(transition: ContainedViewLayoutTransition) {
        self.inputDimNode.alpha = 0.0
        transition.updateAlpha(node: self.inputDimNode, alpha: 1.0)
        transition.animatePositionAdditive(node: self.itemsContainerNode, offset: self.bounds.size.height)
        transition.animatePositionAdditive(node: self.itemsShadowNode, offset: self.bounds.size.height)
        
        self.feedback.impact()
    }
    
    func animateOut(transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        transition.updateAlpha(node: self.inputDimNode, alpha: 0.0)
        let position = CGPoint(x: self.itemsContainerNode.position.x, y: self.bounds.size.height + self.itemsContainerNode.bounds.height)
        transition.updatePosition(node: self.itemsContainerNode, position: position, completion: { _ in
            completion()
        })
        transition.updatePosition(node: self.itemsShadowNode, position: position)
    }
    
    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = layout
        
        var height: CGFloat = max(14.0, layout.intrinsicInsets.bottom)
        
        let inputHeight = layout.inputHeight ?? 0.0
        transition.updateFrame(node: self.inputDimNode, frame: CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - inputHeight), size: CGSize(width: layout.size.width, height: inputHeight)))
        
        height += layout.safeInsets.bottom
        
        var itemsHeight: CGFloat = 0.0
        for actionNode in self.actionNodes {
            actionNode.frame = CGRect(origin: CGPoint(x: 0.0, y: itemsHeight), size: CGSize(width: layout.size.width - 14.0 * 2.0, height: 57.0))
            actionNode.layout()
            itemsHeight += actionNode.bounds.height
        }
        
        let containerFrame = CGRect(origin: CGPoint(x: 14.0, y: layout.size.height - height - itemsHeight), size: CGSize(width: layout.size.width - 14.0 * 2.0, height: itemsHeight))
        transition.updateFrame(node: self.itemsContainerNode, frame: containerFrame)
        transition.updateFrame(node: self.itemsShadowNode, frame: containerFrame.insetBy(dx: -shadowInset, dy: -shadowInset))
        
        height += itemsHeight
        
        height += 6.0
        
        return height
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.itemsContainerNode.frame.contains(point) {
            let subpoint = self.view.convert(point, to: self.itemsContainerNode.view)
            return itemsContainerNode.hitTest(subpoint, with: event)
        }
        if let validLayout = self.validLayout, let inputHeight = validLayout.inputHeight {
            if point.y >= validLayout.size.height - inputHeight {
                return self.inputDimNode.view
            }
        }
        return nil
    }
    
    @objc func actionPressed(_ node: ASDisplayNode) {
        for i in 0 ..< self.actionNodes.count {
            if node == self.actionNodes[i] {
                self.actions[i].action()
                self.dismissed()
                break
            }
        }
    }
    
    @objc func dimTap(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.dismissed()
        }
    }
}
