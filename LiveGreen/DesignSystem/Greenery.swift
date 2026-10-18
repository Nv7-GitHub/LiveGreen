import SwiftUI

/// Hand-drawn field-journal art (ink, gouache and coloured pencil, in `Assets/Greenery`) that frames LiveGreen's
/// screens: foliage hanging from the top, plants along the bottom edge and a few leaves drifting down, on warm paper.
/// The art is fixed, made once with Grok Imagine and cut out of its paper; nothing is generated at run time.
enum GreeneryArt: String {
    case ivyVine = "IvyVine"
    case hangingFern = "HangingFern"
    case blossomBranch = "BlossomBranch"
    case lilyArch = "LilyArch"
    case groundFerns = "GroundFerns"
    case groundMeadow = "GroundMeadow"
    case cornerLeaves = "CornerLeaves"
    case cornerFoxglove = "CornerFoxglove"
    case seedling = "Seedling"
    case terrarium = "Terrarium"
    case sproutingPlug = "SproutingPlug"
    case laurel = "Laurel"
    case ecoIsland = "EcoIsland"

    var image: Image { Image(rawValue) }

    /// Single leaves and petals for `DriftingLeaves`.
    static let leafSprites = ["LeafGinkgo", "LeafBirch", "LeafOlive", "LeafMaple", "LeafWillow", "LeafClover",
                              "LeafFern", "Petal"]
}

/// One piece of art pinned to an edge or corner of the screen.
struct GreeneryPiece {
    var art: GreeneryArt
    /// Width as a share of the screen's (over 1 spills past both sides), capped at `maxWidth` so landscape stays in
    /// proportion.
    var widthShare: CGFloat
    var maxWidth: CGFloat
    var alignment: Alignment
    /// Nudges the piece, mostly to tuck a stem off the edge it grows from.
    var offset = CGSize.zero
    var mirrored = false
    /// Degrees either way the piece sways about the edge it hangs from or grows out of; 0 holds it still.
    var sway: Double = 0
    /// Seconds for one sway, so neighbouring pieces drift out of step.
    var swayDuration: Double = 5
}

/// The art behind one screen. Scenes share the paper, the ink style and the motion; the plants change per tab so
/// each place has its own corner of the garden.
struct GreeneryScene {
    var pieces: [GreeneryPiece] = []
    /// Names from `GreeneryArt.leafSprites`, one drifting leaf each.
    var drifting: [String] = []
    /// Fireflies in Dark Mode.
    var fireflies = false
    /// Extra scroll room at the bottom, so the last content can rest above the plants instead of on them.
    var bottomClearance: CGFloat = 0

    /// History: maidenhair fern by the title, forest floor around the tab bar.
    static let history = GreeneryScene(
        pieces: [
            GreeneryPiece(art: .hangingFern, widthShare: 0.36, maxWidth: 160, alignment: .topTrailing,
                          offset: CGSize(width: 8, height: -36), sway: 1.4, swayDuration: 5.5),
            GreeneryPiece(art: .groundFerns, widthShare: 1.3, maxWidth: 560, alignment: .bottom,
                          offset: CGSize(width: 0, height: 10)),
        ],
        drifting: ["LeafGinkgo", "LeafBirch", "LeafFern"],
        fireflies: true,
        bottomClearance: 40)

    /// Leaderboard: an apple-blossom branch overhead, foxglove and big leaves in the bottom corners.
    static let leaderboard = GreeneryScene(
        pieces: [
            GreeneryPiece(art: .blossomBranch, widthShare: 0.5, maxWidth: 220, alignment: .topTrailing,
                          offset: CGSize(width: 12, height: -14), sway: 1.2, swayDuration: 6),
            GreeneryPiece(art: .cornerFoxglove, widthShare: 0.3, maxWidth: 130, alignment: .bottomLeading,
                          offset: CGSize(width: -14, height: 14), sway: 1, swayDuration: 6.5),
            GreeneryPiece(art: .cornerLeaves, widthShare: 0.34, maxWidth: 150, alignment: .bottomTrailing,
                          offset: CGSize(width: 18, height: 16), sway: 0.8, swayDuration: 7),
        ],
        drifting: ["Petal", "LeafOlive", "Petal"],
        fireflies: true,
        bottomClearance: 64)

    /// Plugs: ivy trailing down from the corner, forest floor below.
    static let plugs = GreeneryScene(
        pieces: [
            GreeneryPiece(art: .ivyVine, widthShare: 0.36, maxWidth: 160, alignment: .topTrailing,
                          offset: CGSize(width: 10, height: -30), mirrored: true, sway: 1.5, swayDuration: 5),
            GreeneryPiece(art: .groundFerns, widthShare: 1.3, maxWidth: 560, alignment: .bottom,
                          offset: CGSize(width: 0, height: 10), mirrored: true),
        ],
        drifting: ["LeafClover", "LeafWillow", "LeafMaple"],
        fireflies: true,
        bottomClearance: 40)

    /// Onboarding: ivy overhead, a wildflower meadow under the Next button, petals and leaves falling.
    static let onboarding = GreeneryScene(
        pieces: [
            GreeneryPiece(art: .ivyVine, widthShare: 0.34, maxWidth: 150, alignment: .topTrailing,
                          offset: CGSize(width: 10, height: -40), mirrored: true, sway: 1.5, swayDuration: 5),
            GreeneryPiece(art: .groundMeadow, widthShare: 1.15, maxWidth: 560, alignment: .bottom,
                          offset: CGSize(width: 0, height: 6)),
        ],
        drifting: ["Petal", "LeafBirch", "LeafMaple", "Petal"],
        fireflies: true)

    /// Settings and About: a fern in the corner and nothing at the bottom, where the form keeps scrolling.
    static let settings = GreeneryScene(
        pieces: [
            GreeneryPiece(art: .hangingFern, widthShare: 0.3, maxWidth: 130, alignment: .topTrailing,
                          offset: CGSize(width: 10, height: -40), sway: 1.2, swayDuration: 6),
        ])

    /// Pushed screens full of numbers (results, swaps, a plug): only the forest floor, so the art stays out of the
    /// way of the content.
    static let detail = GreeneryScene(
        pieces: [
            GreeneryPiece(art: .groundFerns, widthShare: 1.3, maxWidth: 560, alignment: .bottom,
                          offset: CGSize(width: 0, height: 10)),
        ],
        bottomClearance: 40)
}

/// Paper, art and drifting leaves for a scene, filling the screen behind the content. Decoration only: it takes no
/// touches and is hidden from VoiceOver.
struct GreeneryBackdrop: View {
    let scene: GreeneryScene
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PaperBackground()
                ForEach(scene.pieces.indices, id: \.self) { index in
                    piece(scene.pieces[index], in: proxy.size)
                }
                // Ink drawn for paper reads too bright on the dark page; settle it into the shade a little.
                .opacity(colorScheme == .dark ? 0.82 : 1)
                if !scene.drifting.isEmpty || scene.fireflies {
                    DriftingLeaves(sprites: scene.drifting, fireflies: scene.fireflies && colorScheme == .dark)
                }
            }
        }
        // Sheets don't clip their background, and pieces are tucked past the edges.
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func piece(_ piece: GreeneryPiece, in size: CGSize) -> some View {
        piece.art.image
            .resizable()
            .scaledToFit()
            .scaleEffect(x: piece.mirrored ? -1 : 1)
            .frame(width: min(size.width * piece.widthShare, piece.maxWidth))
            .swaying(piece.sway, anchor: UnitPoint(piece.alignment), duration: piece.swayDuration)
            .offset(piece.offset)
            // A fixed frame, not maxWidth: a piece wider than the screen would otherwise widen the whole stack and
            // push the corner pieces off screen.
            .frame(width: size.width, height: size.height, alignment: piece.alignment)
    }
}

/// Warm paper in light mode, deep forest in dark, with a faint dot grid like a field notebook.
struct PaperBackground: View {
    var body: some View {
        Theme.paper
            .overlay {
                Canvas { context, size in
                    let spacing: CGFloat = 22
                    var dots = Path()
                    for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                        for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                            dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                        }
                    }
                    context.fill(dots, with: .foreground)
                }
                .foregroundStyle(Theme.moss.opacity(0.12))
            }
    }
}

extension View {
    /// Puts the scene's paper and art behind this screen. Lists and forms drop their own background so it shows.
    func greeneryBackground(_ scene: GreeneryScene) -> some View {
        scrollContentBackground(.hidden)
            .contentMargins(.bottom, scene.bottomClearance, for: .scrollContent)
            .background { GreeneryBackdrop(scene: scene) }
    }

    /// Rocks the view back and forth by `degrees` about `anchor`, like a plant in a light breeze. Still with
    /// Reduce Motion or when `degrees` is 0.
    func swaying(_ degrees: Double, anchor: UnitPoint, duration: Double = 5) -> some View {
        modifier(Sway(degrees: degrees, anchor: anchor, duration: duration))
    }

    /// Bobs the view up and down by `distance` points, like something floating.
    func floating(_ distance: CGFloat = 5, duration: Double = 3.5) -> some View {
        modifier(Bob(distance: distance, duration: duration))
    }
}

private struct Sway: ViewModifier {
    let degrees: Double
    let anchor: UnitPoint
    let duration: Double
    @State private var swung = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMoving: Bool { degrees != 0 && !reduceMotion }

    func body(content: Content) -> some View {
        // Scoped to the rotation so the repeating animation never catches layout changes.
        content
            .animation(isMoving ? .easeInOut(duration: duration).repeatForever(autoreverses: true) : nil) {
                $0.rotationEffect(.degrees(isMoving ? (swung ? degrees : -degrees) : 0), anchor: anchor)
            }
            .restartingOnAppear($swung)
    }
}

private struct Bob: ViewModifier {
    let distance: CGFloat
    let duration: Double
    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                $0.offset(y: reduceMotion ? 0 : (risen ? -distance : distance))
            }
            .restartingOnAppear($risen)
    }
}

private extension View {
    /// Flips `flag` on when the view appears, starting its repeating animation, and back off without animation
    /// when it leaves, so the motion starts again on return to a tab instead of stopping where it was.
    func restartingOnAppear(_ flag: Binding<Bool>) -> some View {
        onAppear { flag.wrappedValue = true }
            .onDisappear {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { flag.wrappedValue = false }
            }
    }
}

private extension UnitPoint {
    /// The point of a view that sits on the screen edge `alignment` pins it to.
    init(_ alignment: Alignment) {
        let x: CGFloat = alignment.horizontal == .leading ? 0 : alignment.horizontal == .trailing ? 1 : 0.5
        let y: CGFloat = alignment.vertical == .top ? 0 : alignment.vertical == .bottom ? 1 : 0.5
        self.init(x: x, y: y)
    }
}

#Preview("History") {
    NavigationStack {
        List { ForEach(0..<6) { Text("Scan \($0)") } }
            .navigationTitle("History")
            .greeneryBackground(.history)
    }
}

#Preview("Leaderboard, dark") {
    NavigationStack {
        ScrollView { GlassCard { Text("GreenScore").frame(height: 200) }.padding() }
            .navigationTitle("Leaderboard")
            .greeneryBackground(.leaderboard)
    }
    .preferredColorScheme(.dark)
}
