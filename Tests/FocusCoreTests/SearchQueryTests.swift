import FocusCore
import Testing

struct SearchQueryTests {
    @Test
    func resultURLUsesDesktopSearchResults() {
        let query = SearchQuery(keyword: "  原神 测试  ")

        #expect(query.keyword == "原神 测试")
        #expect(query.resultURL.absoluteString == "https://search.bilibili.com/all?keyword=%E5%8E%9F%E7%A5%9E%20%E6%B5%8B%E8%AF%95")
    }
}
