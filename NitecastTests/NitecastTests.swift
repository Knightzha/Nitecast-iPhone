import XCTest
@testable import Nitecast

final class NitecastTests: XCTestCase {
    func testQRAddressNormalizesToServerRoot() throws {
        let value = try ServerAddress.normalize("http://192.168.1.86:8765/phone?source=qr")
        XCTAssertEqual(value.absoluteString,"http://192.168.1.86:8765")
    }
    func testManualAddressGetsDefaultPort() throws {
        XCTAssertEqual(try ServerAddress.normalize("192.168.1.86").port,8765)
        XCTAssertEqual(try ServerAddress.normalize("nitecast-abcdef.local:8770/phone").host,"nitecast-abcdef.local")
    }
    func testUntrustedAndLoopbackAddressesAreRejected() {
        for value in ["https://example.com","file:///etc/passwd","http://user:pass@192.168.1.2:8765","127.0.0.1:8765","localhost:8765","192.168.999.2"] {
            XCTAssertThrowsError(try ServerAddress.normalize(value),value)
        }
    }
    func testResumePrefersLatestUnwatchedProgress() throws {
        let json = #"{"id":"show","name":"A show","items":[{"title":"Ep 1","position":50,"last_played":1,"watched":false,"season":1},{"title":"Ep 2","position":60,"last_played":8,"watched":false,"season":2},{"title":"Ep 3","position":90,"last_played":10,"watched":true,"season":2}]}"#
        let show = try JSONDecoder().decode(MediaCollection.self,from:Data(json.utf8))
        XCTAssertEqual(show.resumeIndex,1)
        XCTAssertEqual(show.seasons,[1,2])
        XCTAssertTrue(show.hasProgress)
        XCTAssertTrue(show.isSeries)
    }
    func testOldSingleItemCollectionBecomesMovie() throws {
        let json = #"{"id":"movie","name":"A movie","items":[{"title":"A movie"}]}"#
        let p = try JSONDecoder().decode(MediaCollection.self,from:Data(json.utf8))
        XCTAssertFalse(p.isSeries)
        XCTAssertEqual(p.resumeIndex,0)
        XCTAssertFalse(p.hasProgress)
    }
    func testEmptyCollectionDoesNotCreateInvalidResumeIndex() throws {
        let p = try JSONDecoder().decode(MediaCollection.self,from:Data(#"{"id":"empty","name":"Empty","items":[]}"#.utf8))
        XCTAssertEqual(p.resumeIndex,0)
        XCTAssertTrue(p.seasons.isEmpty)
    }
    func testV7ServerStateAndNullableVolumeDecode() throws {
        let json = #"{"playlists":[],"devices":["Living room"],"device":"Living room","now":{"pid":null,"index":-1,"state":"","t":0,"dur":0,"vol":null,"error":"","sleep":0,"eoe":false},"dual":{"enabled":false,"audio":"pc","offset":0,"connected":false},"job":{"active":false,"percent":0}}"#
        let state = try JSONDecoder().decode(LibraryState.self,from:Data(json.utf8))
        XCTAssertEqual(state.devices,["Living room"])
        XCTAssertNil(state.now.vol)
        XCTAssertFalse(state.dual!.enabled)
    }
    func testTimeFormatting() {
        XCTAssertEqual(playbackTime(181),"3:01")
        XCTAssertEqual(playbackTime(3605),"1:00:05")
        XCTAssertEqual(playbackTime(-10),"0:00")
        XCTAssertEqual(playbackTime(.nan),"0:00")
    }
}
