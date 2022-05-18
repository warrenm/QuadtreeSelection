import Cocoa
import SpriteKit
import GameplayKit

extension CGRect {
    var gkQuad: GKQuad {
        return GKQuad(quadMin: SIMD2<Float>(Float(origin.x),
                                            Float(origin.y)),
                      quadMax: SIMD2<Float>(Float(origin.x + size.width),
                                            Float(origin.y + size.height)))
    }
}

class ViewController: NSViewController {

    let nodeRadius: CGFloat = 5
    let staticNodeCount = 100
    let dynamicNodeCount = 100
    let sceneWidth: CGFloat = 400
    let sceneHeight: CGFloat = 300

    let unselectableCategoryFlags = 0
    let selectableCategoryFlags = 1

    var skView: SKView!
    var scene: SKScene!
    var dynamicNodes = [SKNode]()
    var selectionNode: SKShapeNode!
    var selectedNodes = Set<SKNode>()
    var quadtree: GKQuadtree<SKNode>!

    var selectionBounds = CGRect.zero
    var mouseDownPosition = CGPoint.zero

    override func viewDidLoad() {
        super.viewDidLoad()

        skView = SKView(frame: view.bounds)
        skView.autoresizingMask = [.width, .height]
        view.addSubview(skView)

        makeScene()
        makeQuadtree()

        // We use event monitoring instead of the ordinary responder chain because SKView also overrides
        // the mouse event methods in NSResponder, preventing us from receiving them by default.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [unowned self] event in
            switch event.type {
            case .leftMouseDown:
                self.mouseDown(with: event)
            case .leftMouseDragged:
                self.mouseDragged(with: event)
            case .leftMouseUp:
                self.mouseUp(with: event)
            default:
                break
            }
            return event
        }
    }

    /// Queries which nodes are intersected by the given rect, using a quadtree
    /// to accelerate the search
    func nodes(in rect: CGRect) -> [SKNode] {
        // First, determine which nodes are potentially in the rect by querying the tree
        let coarseNodes = quadtree.elements(in: rect.gkQuad)
        // Pare down the conservatively-included nodes by tight bounds-checking
        return coarseNodes.filter { node in
            return node.calculateAccumulatedFrame().intersects(rect)
        }
    }

    private func makeScene() {
        scene = SKScene(size: CGSize(width: sceneWidth, height: sceneHeight))
        scene.scaleMode = .aspectFit

        for _ in 0..<staticNodeCount {
            let node = SKShapeNode(circleOfRadius: nodeRadius)
            node.strokeColor = .clear
            node.fillColor = .red
            node.position = CGPoint(x: CGFloat.random(in: 10...390),
                                    y: CGFloat.random(in: 10...290))
            scene.addChild(node)
        }

        for _ in 0..<dynamicNodeCount {
            let node = SKShapeNode(circleOfRadius: nodeRadius)
            node.strokeColor = .clear
            node.fillColor = .green
            node.position = CGPoint(x: CGFloat.random(in: 10...390),
                                    y: CGFloat.random(in: 10...290))
            node.physicsBody = SKPhysicsBody(circleOfRadius: nodeRadius)
            node.physicsBody?.affectedByGravity = false
            node.physicsBody?.friction = 0
            node.physicsBody?.linearDamping = 0
            node.physicsBody?.collisionBitMask = 0
            node.physicsBody?.velocity = CGVector(dx: CGFloat.random(in: -10...10),
                                                  dy: CGFloat.random(in: -10...10))
            scene.addChild(node)
            dynamicNodes.append(node)
        }

        selectionNode = SKShapeNode(rect: CGRect.zero)
        selectionNode.fillColor = .clear
        selectionNode.strokeColor = .white
        selectionNode.isHidden = true
        scene.addChild(selectionNode)

        skView.presentScene(scene)
    }

    private func makeQuadtree() {
        // Choose a cell size that strikes a balance between memory use and granularity
        let cellSize = Float(nodeRadius) * 4

        // Build the initial quadtree by iterating all nodes
        quadtree = GKQuadtree(boundingQuad: scene.calculateAccumulatedFrame().gkQuad,
                              minimumCellSize: cellSize)
        for node in scene.children {
            quadtree.add(node, in: node.calculateAccumulatedFrame().gkQuad)
        }
    }

    private func updateQuadtree() {
        // Update the quadtree by removing and re-adding nodes that may have moved
        for node in dynamicNodes {
            quadtree.remove(node)
            quadtree.add(node, in: node.calculateAccumulatedFrame().gkQuad)
        }
    }

    private func updateSelection() {
        // First, update the quadtree so our selection results are fresh
        updateQuadtree()

        // Update the selected node set
        let previouslySelectedNodes = selectedNodes
        selectedNodes = Set(nodes(in: selectionBounds))

        // Do a little light set theory to determine which nodes were just selected or deselected
        let newlySelectedNodes = selectedNodes.subtracting(previouslySelectedNodes)
        let newlyDeselectedNodes = previouslySelectedNodes.subtracting(selectedNodes)

        // Update selected nodes visually
        for selectedNode in newlySelectedNodes {
            (selectedNode as? SKShapeNode)?.strokeColor = .yellow
        }
        for deselectedNode in newlyDeselectedNodes {
            (deselectedNode as? SKShapeNode)?.strokeColor = .clear
        }

        // Update the selection node to indicate the selected region
        selectionNode.path = CGPath(rect: selectionBounds, transform: nil)
        selectionNode.isHidden = selectionBounds.isEmpty
        selectionNode.strokeColor = .white
    }

    private func updateSelectionBounds(with event: NSEvent) {
        let mousePosition = event.location(in: scene)
        selectionBounds = CGRect(origin: mouseDownPosition,
                                 size: CGSize(width: mousePosition.x - mouseDownPosition.x,
                                              height: mousePosition.y - mouseDownPosition.y)).standardized

        updateSelection()
    }

    // MARK: - NSResponder

    override func mouseDown(with event: NSEvent) {
        mouseDownPosition = event.location(in: scene)
        updateSelectionBounds(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelectionBounds(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateSelectionBounds(with: event)
    }
}

