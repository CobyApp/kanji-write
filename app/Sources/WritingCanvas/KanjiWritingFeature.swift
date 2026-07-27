import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

@Reducer
public struct KanjiWritingFeature {
    @ObservableState
    public struct State: Equatable {
        public let kanji: Kanji
        public var strokePaths: [String] = []
        public var showGuide = true
        public var savedDrawingData: Data?
        public var recognition: RecognitionResult?
        public var isWritingAvailable: Bool { kanji.hasVerifiedStrokeOrder }
        public init(kanji: Kanji) { self.kanji = kanji }
    }

    public enum Action: Equatable {
        case onAppear
        case strokesLoaded([String])
        case toggleGuide
        case drawingLoaded(Data?)
        case saveDrawing(Data)
        case recognize(Data)
        case recognized(RecognitionResult)
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.drawingStore) var drawingStore
    @Dependency(\.kanjiRecognizer) var kanjiRecognizer

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.isWritingAvailable else { return .none }
                let id = state.kanji.id
                return .run { send in
                    async let drawingData = drawingStore.loadDrawing(id)
                    do {
                        await send(.strokesLoaded(try await dictionaryClient.strokeOrder(id)))
                    } catch {
                        // Guide is non-critical: on load failure show no guide;
                        // the writing canvas remains fully usable.
                        await send(.strokesLoaded([]))
                    }
                    await send(.drawingLoaded(await drawingData))
                }
            case let .strokesLoaded(paths):
                state.strokePaths = paths
                return .none
            case .toggleGuide:
                state.showGuide.toggle()
                return .none
            case let .drawingLoaded(data):
                state.savedDrawingData = data
                return .none
            case let .saveDrawing(data):
                let id = state.kanji.id
                return .run { _ in await drawingStore.saveDrawing(id, data) }
            case let .recognize(data):
                let target = state.kanji.literal
                return .run { send in
                    await send(.recognized(kanjiRecognizer.recognize(imageData: data, target: target)))
                }
            case let .recognized(result):
                state.recognition = result
                return .none
            }
        }
    }
}
