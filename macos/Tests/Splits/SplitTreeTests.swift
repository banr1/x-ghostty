import AppKit
import Testing
@testable import XGhostty

class MockView: NSView, Codable, Identifiable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    enum CodingKeys: CodingKey { case id }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        super.init(frame: .zero)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
    }
}

/// A value-type leaf element used to verify `SplitTree` works for non-NSView
/// elements (the F.1 generalization goal). This mirrors the future `GroupRef`.
struct MockRef: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

struct SplitTreeTests {
    /// Creates a two-view horizontal split tree (view1 | view2).
    static func makeHorizontalSplit() throws -> (SplitTree<MockView>, MockView, MockView) {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        return (tree, view1, view2)
    }

    /// Creates a two-view horizontal split tree (view1 | view2).
    private func makeHorizontalSplit() throws -> (SplitTree<MockView>, MockView, MockView) {
        try Self.makeHorizontalSplit()
    }

    // MARK: - Empty and Non-Empty

    @Test func emptyTreeIsEmpty() {
        let tree = SplitTree<MockView>()
        #expect(tree.isEmpty)
    }

    @Test func nonEmptyTreeIsNotEmpty() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        #expect(!tree.isEmpty)
    }

    @Test func isNotSplit() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        #expect(!tree.isSplit)
    }

    @Test func isSplit() throws {
        let (tree, _, _) = try makeHorizontalSplit()
        #expect(tree.isSplit)
    }

    // MARK: - Contains and Find

    @Test func treeContainsView() {
        let view = MockView()
        let tree = SplitTree<MockView>(view: view)
        #expect(tree.contains(.leaf(view: view)))
    }

    @Test func treeDoesNotContainView() {
        let view = MockView()
        let tree = SplitTree<MockView>()
        #expect(!tree.contains(.leaf(view: view)))
    }

    @Test func findsInsertedView() throws {
        let (tree, view1, _) = try makeHorizontalSplit()
        #expect((tree.find(id: view1.id) != nil))
    }

    @Test func doesNotFindUninsertedView() {
        let view1 = MockView()
        let view2 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        #expect((tree.find(id: view2.id) == nil))
    }

    // MARK: - Removing and Replacing

    @Test func treeDoesNotContainRemovedView() throws {
        var (tree, view1, view2) = try makeHorizontalSplit()
        tree = tree.removing(.leaf(view: view1))
        #expect(!tree.contains(.leaf(view: view1)))
        #expect(tree.contains(.leaf(view: view2)))
    }

    @Test func removingNonexistentNodeLeavesTreeUnchanged() {
        let view1 = MockView()
        let view2 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        let result = tree.removing(.leaf(view: view2))
        #expect(result.contains(.leaf(view: view1)))
        #expect(!result.isEmpty)
    }

    @Test func replacingViewShouldRemoveAndInsertView() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        #expect(tree.contains(.leaf(view: view2)))
        let result = try tree.replacing(node: .leaf(view: view2), with: .leaf(view: view3))
        #expect(result.contains(.leaf(view: view1)))
        #expect(!result.contains(.leaf(view: view2)))
        #expect(result.contains(.leaf(view: view3)))
    }

    @Test func replacingViewWithItselfShouldBeAValidOperation() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let result = try tree.replacing(node: .leaf(view: view2), with: .leaf(view: view2))
        #expect(result.contains(.leaf(view: view1)))
        #expect(result.contains(.leaf(view: view2)))
    }

    // MARK: - Focus Target

    @Test func focusTargetOnEmptyTreeReturnsNil() {
        let tree = SplitTree<MockView>()
        let view = MockView()
        let target = tree.focusTarget(for: .next, from: .leaf(view: view))
        #expect(target == nil)
    }

    @Test func focusTargetShouldFindNextFocusedNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .next, from: .leaf(view: view1))
        #expect(target === view2)
    }

    @Test func focusTargetShouldFindItselfWhenOnlyView() throws {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        let target = tree.focusTarget(for: .next, from: .leaf(view: view1))
        #expect(target === view1)
    }

    // When there's no next view, wraps around to the first
    @Test func focusTargetShouldHandleWrappingForNextNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .next, from: .leaf(view: view2))
        #expect(target === view1)
    }

    @Test func focusTargetShouldFindPreviousFocusedNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .previous, from: .leaf(view: view2))
        #expect(target === view1)
    }

    @Test func focusTargetShouldFindSpatialFocusedNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .spatial(.left), from: .leaf(view: view2))
        #expect(target === view1)
    }

    // MARK: - Equalized

    @Test func equalizedAdjustsRatioByLeafCount() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view2, direction: .right)

        guard case .split(let before) = tree.root else {
            Issue.record("unexpected node type")
            return
        }
        #expect(abs(before.ratio - 0.5) < 0.001)

        let equalized = tree.equalized()

        if case .split(let s) = equalized.root {
            #expect(abs(s.ratio - 1.0/3.0) < 0.001)
        }
    }

    // MARK: - Resizing

    @Test(arguments: [
        // (resizeDirection, insertDirection, bounds, pixels, expectedRatio)
        (SplitTree<MockView>.Spatial.Direction.right, SplitTree<MockView>.NewDirection.right,
         CGRect(x: 0, y: 0, width: 1000, height: 500), UInt16(100), 0.6),
        (.left, .right,
         CGRect(x: 0, y: 0, width: 1000, height: 500), UInt16(50), 0.45),
        (.down, .down,
         CGRect(x: 0, y: 0, width: 500, height: 1000), UInt16(200), 0.7),
        (.up, .down,
         CGRect(x: 0, y: 0, width: 500, height: 1000), UInt16(50), 0.45),
    ])
    func resizingAdjustsRatio(
        resizeDirection: SplitTree<MockView>.Spatial.Direction,
        insertDirection: SplitTree<MockView>.NewDirection,
        bounds: CGRect,
        pixels: UInt16,
        expectedRatio: Double
    ) throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: insertDirection)

        let resized = try tree.resizing(node: .leaf(view: view1), by: pixels, in: resizeDirection, with: bounds)

        guard case .split(let s) = resized.root else {
            Issue.record("unexpected node type")
            return
        }
        #expect(abs(s.ratio - expectedRatio) < 0.001)
    }

    // MARK: - Codable

    @Test func encodingAndDecodingPreservesTree() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree<MockView>.self, from: data)
        #expect(decoded.find(id: view1.id) != nil)
        #expect(decoded.find(id: view2.id) != nil)
        #expect(decoded.isSplit)
    }

    @Test func encodingAndDecodingPreservesZoomedPath() throws {
        let (tree, _, view2) = try makeHorizontalSplit()
        let treeWithZoomed = SplitTree<MockView>(root: tree.root, zoomed: .leaf(view: view2))

        let data = try JSONEncoder().encode(treeWithZoomed)
        let decoded = try JSONDecoder().decode(SplitTree<MockView>.self, from: data)

        #expect(decoded.zoomed != nil)
        if case .leaf(let zoomedView) = decoded.zoomed! {
            #expect(zoomedView.id == view2.id)
        } else {
            Issue.record("unexpected node type")
        }
    }

    // MARK: - Collection Conformance

    @Test func treeIteratesLeavesInOrder() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view2, direction: .right)

        #expect(tree.startIndex == 0)
        #expect(tree.endIndex == 3)
        #expect(tree.index(after: 0) == 1)

        #expect(tree[0] === view1)
        #expect(tree[1] === view2)
        #expect(tree[2] === view3)

        var ids: [UUID] = []
        for view in tree {
            ids.append(view.id)
        }
        #expect(ids == [view1.id, view2.id, view3.id])
    }

    @Test func emptyTreeCollectionProperties() {
        let tree = SplitTree<MockView>()

        #expect(tree.startIndex == 0)
        #expect(tree.endIndex == 0)

        var count = 0
        for _ in tree {
            count += 1
        }
        #expect(count == 0)
    }

    // MARK: - Structural Identity

    @Test func structuralIdentityIsReflexive() throws {
        let (tree, _, _) = try makeHorizontalSplit()
        #expect(tree.structuralIdentity == tree.structuralIdentity)
    }

    @Test func structuralIdentityComparesShapeNotRatio() throws {
        let (tree, view1, _) = try makeHorizontalSplit()

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let resized = try tree.resizing(node: .leaf(view: view1), by: 100, in: .right, with: bounds)
        #expect(tree.structuralIdentity == resized.structuralIdentity)
    }

    @Test func structuralIdentityForDifferentStructures() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)

        let expanded = try tree.inserting(view: view3, at: view2, direction: .down)
        #expect(tree.structuralIdentity != expanded.structuralIdentity)
    }

    @Test func structuralIdentityIdentifiesDifferentOrdersShapes() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        let (otherTree, _, _) = try makeHorizontalSplit()
        #expect(tree.structuralIdentity != otherTree.structuralIdentity)
    }

    // MARK: - View Bounds

    @Test func viewBoundsReturnsLeafViewSize() {
        let view1 = MockView()
        view1.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        let tree = SplitTree<MockView>(view: view1)

        let bounds = tree.viewBounds()
        #expect(bounds.width == 500)
        #expect(bounds.height == 300)
    }

    @Test func viewBoundsReturnsZeroForEmptyTree() {
        let tree = SplitTree<MockView>()
        let bounds = tree.viewBounds()

        #expect(bounds.width == 0)
        #expect(bounds.height == 0)
    }

    @Test func viewBoundsHorizontalSplit() throws {
        let view1 = MockView()
        let view2 = MockView()
        view1.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view2.frame = NSRect(x: 0, y: 0, width: 200, height: 500)
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)

        let bounds = tree.viewBounds()
        #expect(bounds.width == 600)
        #expect(bounds.height == 500)
    }

    @Test func viewBoundsVerticalSplit() throws {
        let view1 = MockView()
        let view2 = MockView()
        view1.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        view2.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .down)

        let bounds = tree.viewBounds()
        #expect(bounds.width == 500)
        #expect(bounds.height == 600)
    }

    // MARK: - Node

    @Test func nodeFindsLeaf() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        let node = tree.root?.node(view: view1)
        #expect(node != nil)
        #expect(node == .leaf(view: view1))
    }

    @Test func nodeFindsLeavesInSplitTree() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        #expect(tree.root?.node(view: view1) == .leaf(view: view1))
        #expect(tree.root?.node(view: view2) == .leaf(view: view2))
    }

    @Test func nodeReturnsNilForMissingView() {
        let view1 = MockView()
        let view2 = MockView()

        let tree = SplitTree<MockView>(view: view1)
        #expect(tree.root?.node(view: view2) == nil)
    }

    @Test func resizingUpdatesRatio() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        let resized = SplitTree<MockView>.Node.split(s).resizing(to: 0.7)
        guard case .split(let resizedSplit) = resized else {
            Issue.record("unexpected node type")
            return
        }
        #expect(abs(resizedSplit.ratio - 0.7) < 0.001)
    }

    @Test func resizingLeavesLeafUnchanged() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }
        let resized = root.resizing(to: 0.7)
        #expect(resized == root)
    }

    // MARK: - Spatial

    @Test(arguments: [
        (SplitTree<MockView>.Spatial.Direction.left, SplitTree<MockView>.NewDirection.right),
        (.right, .right),
        (.up, .down),
        (.down, .down),
    ])
    func doesBorderEdge(
        side: SplitTree<MockView>.Spatial.Direction,
        insertDirection: SplitTree<MockView>.NewDirection
    ) throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: insertDirection)

        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 500))

        // view1 borders left/up; view2 borders right/down
        let (borderView, nonBorderView): (MockView, MockView) =
            (side == .right || side == .down) ? (view2, view1) : (view1, view2)
        #expect(spatial.doesBorder(side: side, from: .leaf(view: borderView)))
        #expect(!spatial.doesBorder(side: side, from: .leaf(view: nonBorderView)))
    }

    // MARK: - Calculate View Bounds

    @Test func calculatesViewBoundsForSingleLeaf() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let result = root.calculateViewBounds(in: bounds)
        #expect(result.count == 1)
        #expect(result[0].view === view1)
        #expect(result[0].bounds == bounds)
    }

    @Test func calculatesViewBoundsHorizontalSplit() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let result = root.calculateViewBounds(in: bounds)
        #expect(result.count == 2)

        let leftBounds = result.first { $0.view === view1 }!.bounds
        let rightBounds = result.first { $0.view === view2 }!.bounds
        #expect(leftBounds == CGRect(x: 0, y: 0, width: 500, height: 500))
        #expect(rightBounds == CGRect(x: 500, y: 0, width: 500, height: 500))
    }

    @Test func calculatesViewBoundsVerticalSplit() throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .down)

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: 500, height: 1000)
        let result = root.calculateViewBounds(in: bounds)
        #expect(result.count == 2)

        let topBounds = result.first { $0.view === view1 }!.bounds
        let bottomBounds = result.first { $0.view === view2 }!.bounds
        #expect(topBounds == CGRect(x: 0, y: 500, width: 500, height: 500))
        #expect(bottomBounds == CGRect(x: 0, y: 0, width: 500, height: 500))
    }

    @Test func calculateViewBoundsCustomRatio() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        let resizedRoot = SplitTree<MockView>.Node.split(s).resizing(to: 0.3)
        let container = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let result = resizedRoot.calculateViewBounds(in: container)
        #expect(result.count == 2)

        let leftBounds = result.first { $0.view === view1 }!.bounds
        let rightBounds = result.first { $0.view === view2 }!.bounds
        #expect(leftBounds.width == 300)   // 0.3 * 1000
        #expect(rightBounds.width == 700)   // 0.7 * 1000
        #expect(rightBounds.minX == 300)
    }

    @Test func calculateViewBoundsGrid() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view1, direction: .down)
        tree = try tree.inserting(view: view4, at: view2, direction: .down)
        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }
        let container = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let result = root.calculateViewBounds(in: container)
        #expect(result.count == 4)

        let b1 = result.first { $0.view === view1 }!.bounds
        let b2 = result.first { $0.view === view2 }!.bounds
        let b3 = result.first { $0.view === view3 }!.bounds
        let b4 = result.first { $0.view === view4 }!.bounds
        #expect(b1 == CGRect(x: 0, y: 400, width: 500, height: 400))   // top-left
        #expect(b2 == CGRect(x: 500, y: 400, width: 500, height: 400)) // top-right
        #expect(b3 == CGRect(x: 0, y: 0, width: 500, height: 400))     // bottom-left
        #expect(b4 == CGRect(x: 500, y: 0, width: 500, height: 400))   // bottom-right
    }

    @Test(arguments: [
        (SplitTree<MockView>.Spatial.Direction.right, SplitTree<MockView>.NewDirection.right),
        (.left, .right),
        (.down, .down),
        (.up, .down),
    ])
    func slotsFromNode(
        direction: SplitTree<MockView>.Spatial.Direction,
        insertDirection: SplitTree<MockView>.NewDirection
    ) throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: insertDirection)

        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 500))

        // look from view1 toward view2 for right/down, from view2 toward view1 for left/up
        let (fromView, expectedView): (MockView, MockView) =
            (direction == .right || direction == .down) ? (view1, view2) : (view2, view1)
        let slots = spatial.slots(in: direction, from: .leaf(view: fromView))
        #expect(slots.count == 1)
        #expect(slots[0].node == .leaf(view: expectedView))
    }

    @Test func slotsGridFromTopLeft() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view1, direction: .down)
        tree = try tree.inserting(view: view4, at: view2, direction: .down)
        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 800))
        let rightSlots = spatial.slots(in: .right, from: .leaf(view: view1))
        let downSlots = spatial.slots(in: .down, from: .leaf(view: view1))
        // slots() returns both split nodes and leaves; split nodes can tie on distance
        #expect(rightSlots.contains { $0.node == .leaf(view: view2) })
        #expect(downSlots.contains { $0.node == .leaf(view: view3) })
    }

    @Test func slotsGridFromBottomRight() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view1, direction: .down)
        tree = try tree.inserting(view: view4, at: view2, direction: .down)
        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 800))
        let leftSlots = spatial.slots(in: .left, from: .leaf(view: view4))
        let upSlots = spatial.slots(in: .up, from: .leaf(view: view4))
        #expect(leftSlots.contains { $0.node == .leaf(view: view3) })
        #expect(upSlots.contains { $0.node == .leaf(view: view2) })
    }

    @Test func slotsReturnsEmptyWhenNoNodesInDirection() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 500))
        #expect(spatial.slots(in: .left, from: .leaf(view: view1)).isEmpty)
        #expect(spatial.slots(in: .right, from: .leaf(view: view2)).isEmpty)
        #expect(spatial.slots(in: .up, from: .leaf(view: view1)).isEmpty)
        #expect(spatial.slots(in: .down, from: .leaf(view: view2)).isEmpty)
    }

    // Set/Dictionary usage is the only path that exercises StructuralIdentity.hash(into:)
    @Test func structuralIdentityHashableBehavior() throws {
        let (tree, _, _) = try makeHorizontalSplit()
        let id = tree.structuralIdentity

        #expect(id == id)

        var seen: Set<SplitTree<MockView>.StructuralIdentity> = []
        seen.insert(id)
        seen.insert(id)
        #expect(seen.count == 1)

        var cache: [SplitTree<MockView>.StructuralIdentity: String] = [:]
        cache[id] = "two-pane"
        #expect(cache[id] == "two-pane")
    }

    @Test func nodeStructuralIdentityInSet() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        var nodeIds: Set<SplitTree<MockView>.Node.StructuralIdentity> = []
        nodeIds.insert(tree.root!.structuralIdentity)
        nodeIds.insert(s.left.structuralIdentity)
        nodeIds.insert(s.right.structuralIdentity)
        #expect(nodeIds.count == 3)
    }

    @Test func nodeStructuralIdentityDistinguishesLeaves() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        var nodeIds: Set<SplitTree<MockView>.Node.StructuralIdentity> = []
        nodeIds.insert(s.left.structuralIdentity)
        nodeIds.insert(s.right.structuralIdentity)
        #expect(nodeIds.count == 2)
    }

    // MARK: - Group-Layer Helpers (F.2)

    /// Builds a horizontal split of value-type refs: (a | b).
    static func makeRefSplit() throws -> (SplitTree<MockRef>, MockRef, MockRef) {
        let a = MockRef()
        let b = MockRef()
        var tree = SplitTree<MockRef>(view: a)
        tree = try tree.inserting(view: b, at: a, direction: .right)
        return (tree, a, b)
    }

    /// Builds a horizontal row of three value-type refs: (a | b | c).
    /// Returns the tree and its leftmost-to-rightmost refs `[a, b, c]`.
    static func makeRefRow() throws -> (tree: SplitTree<MockRef>, refs: [MockRef]) {
        let a = MockRef()
        let b = MockRef()
        let c = MockRef()
        var tree = SplitTree<MockRef>(view: a)
        tree = try tree.inserting(view: b, at: a, direction: .right)
        tree = try tree.inserting(view: c, at: b, direction: .right)
        return (tree, [a, b, c])
    }

    // --- Value-type element support (F.1 generalization goal) ---

    @Test func valueTypeElementBuildsAndFinds() throws {
        let (tree, a, b) = try Self.makeRefSplit()
        #expect(tree.isSplit)
        #expect(tree.find(id: a.id) != nil)
        #expect(tree.find(id: b.id) != nil)
        #expect(tree.find(id: MockRef().id) == nil)
    }

    @Test func valueTypeLeafEqualityIsByValue() {
        let id = UUID()
        let leftLeaf = SplitTree<MockRef>.Node.leaf(view: MockRef(id: id))
        let rightLeaf = SplitTree<MockRef>.Node.leaf(view: MockRef(id: id))
        // Distinct instances, same id -> equal by value (unlike NSView identity).
        #expect(leftLeaf == rightLeaf)
        #expect(leftLeaf.structuralIdentity == rightLeaf.structuralIdentity)
    }

    @Test func valueTypeCodableRoundTrips() throws {
        let (tree, a, b) = try Self.makeRefSplit()
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree<MockRef>.self, from: data)
        #expect(decoded.find(id: a.id) != nil)
        #expect(decoded.find(id: b.id) != nil)
        #expect(decoded.isSplit)
    }

    // --- firstLeaf ---

    @Test func firstLeafReturnsLeftmost() throws {
        let (tree, refs) = try Self.makeRefRow()
        #expect(tree.firstLeaf?.id == refs[0].id)
    }

    @Test func firstLeafIsNilForEmptyTree() {
        let tree = SplitTree<MockRef>()
        #expect(tree.firstLeaf == nil)
    }

    // --- spatialNeighbor ---

    @Test(arguments: [
        (SplitTree<MockRef>.Spatial.Direction.right, SplitTree<MockRef>.NewDirection.right),
        (.left, .right),
        (.up, .down),
        (.down, .down),
    ])
    func spatialNeighborFindsAdjacent(
        direction: SplitTree<MockRef>.Spatial.Direction,
        insertDirection: SplitTree<MockRef>.NewDirection
    ) throws {
        let a = MockRef()
        let b = MockRef()
        var tree = SplitTree<MockRef>(view: a)
        tree = try tree.inserting(view: b, at: a, direction: insertDirection)

        let (from, expected): (MockRef, MockRef) =
            (direction == .right || direction == .down) ? (a, b) : (b, a)
        #expect(tree.spatialNeighbor(from: from, direction: direction)?.id == expected.id)
    }

    @Test func spatialNeighborReturnsNilWhenNone() throws {
        let (tree, a, b) = try Self.makeRefSplit()
        #expect(tree.spatialNeighbor(from: a, direction: .left) == nil)
        #expect(tree.spatialNeighbor(from: b, direction: .right) == nil)
        #expect(tree.spatialNeighbor(from: a, direction: .up) == nil)
    }

    // --- lowestCommonSplitPath ---

    @Test func lowestCommonSplitPathReturnsRootForSiblings() throws {
        let (tree, a, b) = try Self.makeRefSplit()
        let path = tree.lowestCommonSplitPath(between: a, and: b, matchingResizeDirection: .right)
        #expect(path != nil)
        #expect(path?.isEmpty == true) // the root split separates the siblings
    }

    @Test func lowestCommonSplitPathNilWhenDirectionMismatches() throws {
        let (tree, a, b) = try Self.makeRefSplit() // horizontal split
        // Resizing vertically across a horizontal boundary has no matching split.
        #expect(tree.lowestCommonSplitPath(between: a, and: b, matchingResizeDirection: .up) == nil)
        #expect(tree.lowestCommonSplitPath(between: a, and: b, matchingResizeDirection: .down) == nil)
    }

    @Test func lowestCommonSplitPathFindsNestedBoundary() throws {
        // Layout: a | (b / c) -- a on the left, b stacked over c on the right.
        let a = MockRef()
        let b = MockRef()
        let c = MockRef()
        var tree = SplitTree<MockRef>(view: a)
        tree = try tree.inserting(view: b, at: a, direction: .right)
        tree = try tree.inserting(view: c, at: b, direction: .down)

        // a and b are separated by the root horizontal split.
        let ab = tree.lowestCommonSplitPath(between: a, and: b, matchingResizeDirection: .right)
        #expect(ab?.isEmpty == true)
        // b and c are separated by the nested vertical split (not the root).
        let bc = tree.lowestCommonSplitPath(between: b, and: c, matchingResizeDirection: .down)
        #expect(bc != nil)
        #expect(bc?.isEmpty == false)
        // b and c are not separated along the horizontal axis.
        #expect(tree.lowestCommonSplitPath(between: b, and: c, matchingResizeDirection: .right) == nil)
    }

    // --- adjustRatio ---

    @Test func adjustRatioGrowsAndShrinksLeadingChild() throws {
        let (tree, _, _) = try Self.makeRefSplit()
        let rootPath = SplitTree<MockRef>.Path(path: [])

        let grown = tree.adjustRatio(at: rootPath, direction: .right, amount: 0.1)
        guard case .split(let g) = grown.root else { Issue.record("expected split"); return }
        #expect(abs(g.ratio - 0.6) < 0.001)

        let shrunk = tree.adjustRatio(at: rootPath, direction: .left, amount: 0.1)
        guard case .split(let s) = shrunk.root else { Issue.record("expected split"); return }
        #expect(abs(s.ratio - 0.4) < 0.001)
    }

    @Test func adjustRatioClampsToBounds() throws {
        let (tree, _, _) = try Self.makeRefSplit()
        let rootPath = SplitTree<MockRef>.Path(path: [])

        let maxed = tree.adjustRatio(at: rootPath, direction: .right, amount: 1.0)
        guard case .split(let m) = maxed.root else { Issue.record("expected split"); return }
        #expect(abs(m.ratio - 0.9) < 0.001)
    }

    @Test func adjustRatioIsNoopForLeafPath() {
        let leaf = MockRef()
        let tree = SplitTree<MockRef>(view: leaf)
        let result = tree.adjustRatio(at: SplitTree<MockRef>.Path(path: []), direction: .right, amount: 0.1)
        // The root is a leaf; there is nothing to resize.
        #expect(result.find(id: leaf.id) != nil)
        if case .split = result.root { Issue.record("leaf root must not become a split") }
    }

    // --- pruningLeaves ---

    @Test func pruningLeavesRemovesMatchingAndCollapses() throws {
        let (tree, refs) = try Self.makeRefRow()
        let (a, b, c) = (refs[0], refs[1], refs[2])
        let pruned = tree.pruningLeaves { $0.id == b.id }

        #expect(pruned.find(id: a.id) != nil)
        #expect(pruned.find(id: c.id) != nil)
        #expect(pruned.find(id: b.id) == nil)
        // a and c survive; the collapsed tree is a single split of the two.
        #expect(pruned.count == 2)
    }

    @Test func pruningAllLeavesYieldsEmptyTree() throws {
        let (tree, _, _) = try Self.makeRefSplit()
        let pruned = tree.pruningLeaves { _ in true }
        #expect(pruned.isEmpty)
    }

    @Test func pruningNoLeavesIsUnchanged() throws {
        let (tree, a, b) = try Self.makeRefSplit()
        let pruned = tree.pruningLeaves { _ in false }
        #expect(pruned.find(id: a.id) != nil)
        #expect(pruned.find(id: b.id) != nil)
        #expect(pruned.isSplit)
    }

    @Test func pruningLeavesClearsZoomedWhenPruned() throws {
        let (tree, _, b) = try Self.makeRefSplit()
        let zoomed = SplitTree<MockRef>(root: tree.root, zoomed: .leaf(view: b))
        let pruned = zoomed.pruningLeaves { $0.id == b.id }
        #expect(pruned.zoomed == nil)
    }

    // --- subtreeContainingOnly / treeContainingOnly ---

    @Test func subtreeContainingOnlyReturnsSingleLeaf() throws {
        let (tree, a, b) = try Self.makeRefSplit()
        let only = tree.subtreeContainingOnly(a)
        #expect(only.find(id: a.id) != nil)
        #expect(only.find(id: b.id) == nil)
        #expect(!only.isSplit)
        #expect(only.zoomed == nil)
    }

    @Test func treeContainingOnlyMatchesSubtreeContainingOnly() throws {
        let (tree, a, _) = try Self.makeRefSplit()
        let viaSubtree = tree.subtreeContainingOnly(a)
        let viaTree = tree.treeContainingOnly(a)
        #expect(viaTree.structuralIdentity == viaSubtree.structuralIdentity)
    }

    @Test func containingOnlyAbsentElementIsEmpty() throws {
        let (tree, _, _) = try Self.makeRefSplit()
        let only = tree.subtreeContainingOnly(MockRef())
        #expect(only.isEmpty)
    }

    // --- nearestLeaf ---

    @Test func nearestLeafFindsClosestExcludingSelf() throws {
        let (tree, refs) = try Self.makeRefRow() // a | b | c, a is leftmost
        let (a, b) = (refs[0], refs[1])
        // The nearest leaf to a (excluding a) is its immediate neighbor b.
        #expect(tree.nearestLeaf(to: a, matching: { _ in true })?.id == b.id)
    }

    @Test func nearestLeafRespectsPredicate() throws {
        let (tree, refs) = try Self.makeRefRow()
        let (a, b, c) = (refs[0], refs[1], refs[2])
        // Excluding the nearest (b) yields the next nearest (c).
        let next = tree.nearestLeaf(to: a, matching: { $0.id != b.id })
        #expect(next?.id == c.id)
    }

    @Test func nearestLeafReturnsNilWhenNoneMatch() throws {
        let (tree, refs) = try Self.makeRefRow()
        let a = refs[0]
        // No leaf other than a satisfies the predicate.
        #expect(tree.nearestLeaf(to: a, matching: { $0.id == a.id }) == nil)
    }
}
