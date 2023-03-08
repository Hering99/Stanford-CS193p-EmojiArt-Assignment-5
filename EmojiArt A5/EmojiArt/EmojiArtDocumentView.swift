//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by CS193p Instructor on 4/26/21.
//  Copyright © 2021 Stanford University. All rights reserved.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    
    let defaultEmojiFontSize: CGFloat = 40
    
    var body: some View {
        VStack(spacing: 0) {
            documentBody
            palette
        }
    }
    
    var documentBody: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.overlay(
                    OptionalImage(uiImage: document.backgroundImage)
                        .scaleEffect(selectedEmojis.isEmpty ? zoomScale : steadyStateZoomScale)
                        .position(convertFromEmojiCoordinates((0,0), in: geometry))
                )
                .gesture(doubleTapToZoom(in: geometry.size).exclusively(before: deselectAll()))
                
                if document.backgroundImageFetchStatus == .fetching {
                    ProgressView().scaleEffect(2)
                } else {
                    ForEach(document.emojis) { emoji in
                        Text(emoji.text)
                            .padding(5)
                            .font(.system(size: fontSize(for: emoji)))
                            .border(.blue.opacity(selectionBorder(for: emoji)), width: getZoomScaleForEmoji(emoji)*5)
                            .scaleEffect(getZoomScaleForEmoji(emoji))
                            .position(position(for: emoji, in: geometry))
                            .gesture(selectGesture(on: emoji).simultaneously(with: deleteGesture(on: emoji).simultaneously(with: selectedEmojis.contains(emoji) ? emojiPanGesture(on: emoji) : nil)))
                        }
                    }
                }
                .clipped()
                .onDrop(of: [.plainText,.url,.image], isTargeted: nil) { providers, location in
                    drop(providers: providers, at: location, in: geometry)
            }
            .gesture(zoomGesture().simultaneously(with: gestureEmojiPanOffset == CGSize.zero ? panGesture() : nil))
        }
    }
    
    // MARK: - Select and Deselect
    
    @State var selectedEmojisId = Set<Int>()
    
    var selectedSize: CGFloat = 6
    
    private var selectedEmojis: Set<EmojiArtModel.Emoji> {
        var selectedEmojis = Set<EmojiArtModel.Emoji>()
        for id in selectedEmojisId {
            selectedEmojis.insert(document.emojis.first(where: {$0.id == id})!)
        }
        return selectedEmojis
    }
    
    private func selectGesture(on emoji: EmojiArtModel.Emoji) -> some Gesture {
        TapGesture()
            .onEnded {
                withAnimation {
                    selectedEmojisId.toggleMembership(of: emoji.id)
                }
            }
    }
    
    private func deselectAll() -> some Gesture {
        TapGesture()
            .onEnded {
                withAnimation {
                    selectedEmojisId = []
                }
            }
    }
    
    //have an border on the emoji to show if it is selected. The opacity of said border changes from 0 to 1 if it
    //gets selected
    private func selectionBorder(for emoji: EmojiArtModel.Emoji) -> Double {
        if selectedEmojisId.contains(emoji.id) { return 1.0 }
        else { return 0 }
    }
    
    // MARK: - Drag and Drop
    
    private func drop(providers: [NSItemProvider], at location: CGPoint, in geometry: GeometryProxy) -> Bool {
        var found = providers.loadObjects(ofType: URL.self) { url in
            document.setBackground(.url(url.imageURL))
        }
        if !found {
            found = providers.loadObjects(ofType: UIImage.self) { image in
                if let data = image.jpegData(compressionQuality: 1.0) {
                    document.setBackground(.imageData(data))
                }
            }
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                if let emoji = string.first, emoji.isEmoji {
                    document.addEmoji(
                        String(emoji),
                        at: convertToEmojiCoordinates(location, in: geometry),
                        size: defaultEmojiFontSize / zoomScale
                    )
                }
            }
        }
        return found
    }
    
    // MARK: - Positioning/Sizing Emoji
    
    private func position(for emoji: EmojiArtModel.Emoji, in geometry: GeometryProxy) -> CGPoint {
        if selectedEmojis.contains(emoji) {
            return convertFromEmojiCoordinates((emoji.x + Int(gestureEmojiPanOffset.width), emoji.y + Int(gestureEmojiPanOffset.height)), in: geometry)
        }
        else {
            return convertFromEmojiCoordinates((emoji.x, emoji.y), in: geometry)
        }
    }
    
    private func fontSize(for emoji: EmojiArtModel.Emoji) -> CGFloat {
        CGFloat(emoji.size)
    }
    
    private func convertToEmojiCoordinates(_ location: CGPoint, in geometry: GeometryProxy) -> (x: Int, y: Int) {
        let center = geometry.frame(in: .local).center
        let location = CGPoint(
            x: (location.x - panOffset.width - center.x) / zoomScale,
            y: (location.y - panOffset.height - center.y) / zoomScale
        )
        return (Int(location.x), Int(location.y))
    }
    
    private func convertFromEmojiCoordinates(_ location: (x: Int, y: Int), in geometry: GeometryProxy) -> CGPoint {
        let center = geometry.frame(in: .local).center
        return CGPoint(
            x: center.x + CGFloat(location.x) * zoomScale + panOffset.width,
            y: center.y + CGFloat(location.y) * zoomScale + panOffset.height
        )
    }
    
    // MARK: - Zooming
    
    @State private var steadyStateZoomScale: CGFloat = 1
    @GestureState private var gestureZoomScale: CGFloat = 1
    
    private var zoomScale: CGFloat {
        steadyStateZoomScale * gestureZoomScale
    }
    
    private func getZoomScaleForEmoji(_ emoji: EmojiArtModel.Emoji) -> CGFloat {
        selectedEmojis.isEmpty ? zoomScale : selectedEmojis.contains(emoji) ? zoomScale : steadyStateZoomScale
    }
    
    private func zoomGesture() -> some Gesture {
            MagnificationGesture()
                .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, _ in
                    gestureZoomScale = latestGestureScale
                }
                .onEnded { gestureScaleAtEnd in
                    if selectedEmojisId.isEmpty {
                        steadyStateZoomScale *= gestureScaleAtEnd
                    }
                    else {
                        for emoji in selectedEmojis {
                            document.scaleEmoji(emoji, by: gestureScaleAtEnd)
                        }
                    }
                }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
            TapGesture(count: 2)
                .onEnded {
                    withAnimation {
                            zoomToFit(document.backgroundImage, in: size)
                        }
                }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0  {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            steadyStatePanOffset = .zero
            steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
    
    // MARK: - Panning
    
    @State private var steadyStatePanOffset: CGSize = CGSize.zero
    @GestureState private var gesturePanOffset: CGSize = CGSize.zero
    @GestureState private var gestureEmojiPanOffset: CGSize = CGSize.zero
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, _ in
                gesturePanOffset = latestDragGestureValue.translation / zoomScale
            }
            .onEnded { finalDragGestureValue in
                steadyStatePanOffset = steadyStatePanOffset + (finalDragGestureValue.translation / zoomScale)
            }
    }
    
    private func emojiPanGesture(on emoji: EmojiArtModel.Emoji) -> some Gesture {
        DragGesture()
            .updating($gestureEmojiPanOffset) { latestDragGestureValue, gestureEmojiPanOffset, _ in
                    gestureEmojiPanOffset = latestDragGestureValue.distance / zoomScale
            }
            .onEnded { finalDragGestureValue in
                for emoji in selectedEmojis {
                    document.moveEmoji(emoji, by: finalDragGestureValue.distance / zoomScale)
                }
            }
    }
    
    // MARK: - Delete
    
    private func deleteGesture(on emoji: EmojiArtModel.Emoji) -> some Gesture {
        LongPressGesture( minimumDuration: 0.8)
            .onEnded { _ in
                document.removeEmoji(emoji)
            }
    }
    
    // MARK: - Palette
    
    var palette: some View {
            ScrollingEmojisView(emojis: testEmojis).font(.system(size: defaultEmojiFontSize))
    }

    let testEmojis = "😀😷🦠💉👻👀🐶🌲🌎🌞🔥🍎⚽️🚗🚓🚲🛩🚁🚀🛸🏠⌚️🎁🗝🔐❤️⛔️❌❓✅⚠️🎶➕➖🏳️"
}

struct ScrollingEmojisView: View {

    let emojis: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(emojis.map { String($0) }, id: \.self) { emoji in
                    Text(emoji)
                        .onDrag { NSItemProvider(object: emoji as NSString) }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        EmojiArtDocumentView(document: EmojiArtDocument())
    }
}
