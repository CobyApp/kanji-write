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
        public init(kanji: Kanji) { self.kanji = kanji }
    }

    public enum Action: Equatable {
        case onAppear
        case strokesLoaded([String])
        case toggleGuide
        case drawingLoaded(Data?)
        case saveDrawing(Data)
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.drawingStore) var drawingStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
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
            }
        }
    }
}
