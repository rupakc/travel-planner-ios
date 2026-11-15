import Foundation
import Testing

@testable import VoyagerModel

private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
}

/// Every example of `Social-API.md` (profile, follow, ideas, comments), plus the lenient-decoding rules.
@Suite struct Phase5SocialModelsTests {
    @Test func test_ownProfileExample() throws {
        let profile = try decode(
            OwnProfile.self,
            """
            {"handle": "maria_k", "visibility": "followers", "bio": "Slow travel", "show_avatar": true,
             "show_home_country": false, "show_countries": true, "show_level": false, "show_badges": false,
             "leaderboard_opt_in": true, "home_country": "ES", "created_at": "2026-11-12T10:00:00Z"}
            """)
        #expect(profile.hasProfile && profile.handle == "maria_k" && profile.visibility == .followers)
        #expect(profile.showAvatar && profile.showCountries && profile.leaderboardOptIn && profile.homeCountry == "ES")
    }

    @Test func test_everyToggleDefaultsOff() throws {
        for text in [#"{"handle": null}"#, "{}", #"{"handle": null, "visibility": "weird", "show_avatar": null}"#] {
            let profile = try decode(OwnProfile.self, text)
            #expect(!profile.hasProfile && profile.visibility == .private && profile.bio.isEmpty)
            #expect(!profile.showAvatar && !profile.showHomeCountry && !profile.showCountries)
            #expect(!profile.showLevel && !profile.showBadges && !profile.leaderboardOptIn && profile.homeCountry == nil)
        }
        let blank = OwnProfile()
        #expect(blank.visibility == .private && !blank.showAvatar && !blank.leaderboardOptIn)
    }

    @Test func test_profilePatchSendsOnlyWhatIsSet() throws {
        let data = try JSONEncoder().encode(ProfilePatch(handle: "maria_k", visibility: .public, showLevel: false))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(json.object?.count == 3)
        #expect(json["handle"].string == "maria_k" && json["visibility"].string == "public" && json["show_level"].bool == false)
        let empty = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(ProfilePatch()))
        #expect(empty.object?.isEmpty == true)
    }

    @Test func test_handleCheck() throws {
        #expect(try decode(HandleCheck.self, #"{"available": true}"#) == HandleCheck(available: true))
        #expect(try decode(HandleCheck.self, #"{"available": false, "reason": "taken"}"#).reason == .taken)
        #expect(try decode(HandleCheck.self, #"{"available": false, "reason": "reserved"}"#).reason == .reserved)
        #expect(try decode(HandleCheck.self, #"{"available": false, "reason": "brand_new"}"#).reason == .unknown("brand_new"))
        #expect(throws: DecodingError.self) { try decode(HandleCheck.self, "{}") }
    }

    @Test func test_optionalProfileFieldsAbsent() throws {
        let minimal = try decode(
            PublicProfile.self,
            """
            {"handle": "pat", "bio": "", "ideas_count": 2, "followers_count": 5, "following_count": 1,
             "you": {"following": false, "pending": false, "follows_you": false, "blocked": false}}
            """)
        #expect(minimal.avatarURL == nil && minimal.homeCountry == nil && minimal.countries == nil)
        #expect(minimal.level == nil && minimal.badges == nil)
        #expect(minimal.ideasCount == 2 && minimal.followersCount == 5 && minimal.followingCount == 1)
        let bare = try decode(PublicProfile.self, #"{"handle": "pat"}"#)
        #expect(bare.ideasCount == 0 && bare.you == ProfileRelation() && bare.bio.isEmpty)
    }

    @Test func test_publicProfileExampleWithEveryOptIn() throws {
        let profile = try decode(
            PublicProfile.self,
            """
            {"handle": "maria_k", "bio": "Hi", "avatar_url": "/api/avatars/9", "home_country": "ES",
             "countries": ["JP", "PT"], "level": 4, "badges": [{"id": "inspirer", "tier": "bronze"}, {"id": "muse"}, {"nope": 1}],
             "ideas_count": 3, "followers_count": "12", "following_count": 7,
             "you": {"following": true, "pending": false, "follows_you": true, "blocked": false}}
            """)
        #expect(profile.avatarURL == "/api/avatars/9" && profile.homeCountry == "ES" && profile.countries == ["JP", "PT"])
        #expect(profile.level == 4 && profile.badges == [ProfileBadge(id: "inspirer", tier: "bronze"), ProfileBadge(id: "muse")])
        #expect(profile.followersCount == 12 && profile.you.following && profile.you.followsYou && !profile.you.pending)
        #expect(throws: DecodingError.self) { try decode(PublicProfile.self, #"{"bio": "no handle"}"#) }
    }

    @Test func test_followAnswerAndRequests() throws {
        #expect(try decode(FollowAnswer.self, #"{"state": "following"}"#).state == .following)
        #expect(try decode(FollowAnswer.self, #"{"state": "pending"}"#).state == .pending)
        #expect(try decode(FollowAnswer.self, #"{"state": "future"}"#).state == .pending)
        let list = try decode(
            FollowRequestList.self,
            #"{"requests": [{"handle": "a", "created_at": "2026-11-12T10:00:00Z"}, {"x": 1}, {"handle": "b"}]}"#)
        #expect(list.requests.map(\.handle) == ["a", "b"])
    }

    @Test func test_userPagesDropBrokenRowsAndKeepTheCursor() throws {
        let page = try decode(UserPage.self, #"{"users": [{"handle": "a"}, {}, {"handle": "b"}], "next": "c9"}"#)
        #expect(page.users.map(\.handle) == ["a", "b"] && page.next == "c9")
        #expect(try decode(UserPage.self, #"{"users": [], "next": null}"#).next == nil)
        #expect(try decode(UserPage.self, #"{"users": [], "next": 20}"#).next == "20")
        #expect(try decode(UserPage.self, #"{"users": [{"handle": "blocked"}]}"#).next == nil)
    }

    private let ideaJSON = """
        {"id": "i1", "kind": "plan", "title": "Tokyo in 5 days", "caption": "Ramen", "author": {"handle": "maria_k"},
         "snapshot": {"days": 5, "destinations": ["Tokyo"]}, "likes": 3, "saves": 1, "comments": 2,
         "liked": true, "saved": false, "mine": false, "status": "published", "created_at": "2026-11-12T10:00:00Z"}
        """

    @Test func test_ideaExample() throws {
        let idea = try decode(Idea.self, ideaJSON)
        #expect(idea.id == "i1" && idea.kind == .plan && idea.title == "Tokyo in 5 days" && idea.author.handle == "maria_k")
        #expect(idea.author.avatarURL == nil && idea.likes == 3 && idea.saves == 1 && idea.comments == 2)
        #expect(idea.liked && !idea.saved && !idea.mine && idea.status.isPublished)
        #expect(idea.snapshot["days"].int == 5)
    }

    @Test func test_ideaStatusesAndUnknowns() throws {
        func idea(_ status: String) throws -> Idea {
            try decode(Idea.self, #"{"id": 7, "kind": "poster", "title": "t", "author": {"handle": "a"}, "status": "\#(status)"}"#)
        }
        #expect(try idea("held").status == .held)
        #expect(try idea("hidden").status == .hidden)
        #expect(try idea("removed").status == .removed)
        let unknown = try idea("quarantined")
        #expect(unknown.status == .unknown("quarantined") && !unknown.status.isPublished)
        #expect(unknown.id == "7" && unknown.kind == .unknown("poster"))
        let noStatus = try decode(Idea.self, #"{"id": "9", "title": "t", "author": {"handle": "a"}}"#)
        #expect(noStatus.status.isPublished)
        #expect(throws: DecodingError.self) { try decode(Idea.self, #"{"id": "9", "title": "no author"}"#) }
    }

    @Test func test_cursorPaging() throws {
        let page = try decode(IdeaPage.self, #"{"ideas": [\#(ideaJSON), {"broken": true}], "next": "40"}"#)
        #expect(page.ideas.map(\.id) == ["i1"] && page.next == "40")
        let last = try decode(IdeaPage.self, #"{"ideas": [], "next": null}"#)
        #expect(last.ideas.isEmpty && last.next == nil)
    }

    @Test func test_commentsOldestFirstAsSent() throws {
        let page = try decode(
            CommentPage.self,
            """
            {"comments": [{"id": "c1", "author": {"handle": "a"}, "text": "Nice", "helpful": true, "mine": false, "created_at": "x"},
                          {"id": "c2", "author": {"handle": "b"}, "text": "Ok", "status": "held", "mine": true}, {"id": "c3"}],
             "next": null}
            """)
        #expect(page.comments.map(\.id) == ["c1", "c2"] && page.comments[0].helpful && page.comments[1].mine)
        #expect(page.comments[1].status == .held && page.next == nil)
    }

    @Test func test_savedIdeaIsAPlanID() throws {
        #expect(try decode(SavedIdea.self, #"{"plan_id": 42}"#).planID == 42)
        #expect(throws: DecodingError.self) { try decode(SavedIdea.self, "{}") }
    }

    @Test func test_draftEncodingMatchesTheContract() throws {
        let draft = IdeaDraft(planID: 5, kind: .recap, title: "T", caption: "C", locale: "de")
        let json = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(draft))
        #expect(json["plan_id"].int == 5 && json["kind"].string == "recap" && json["title"].string == "T")
        #expect(json["caption"].string == "C" && json["locale"].string == "de")
        #expect(IdeaDraft.maxTitle == 80 && IdeaDraft.maxCaption == 500)
    }

    @Test func test_everyReportReasonIsInTheContract() throws {
        #expect(ReportReason.allCases.map(\.rawValue) == ["spam", "abuse", "sexual", "violence", "misinformation", "other"])
        #expect(ReportTarget.allCases.map(\.rawValue) == ["idea", "comment", "profile"])
        let long = String(repeating: "x", count: 300)
        let request = ReportRequest(target: .profile, id: "maria_k", reason: .abuse, note: "  " + long + "  ")
        let json = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(request))
        #expect(json["target"].string == "profile" && json["id"].string == "maria_k" && json["reason"].string == "abuse")
        #expect(json["note"].string?.count == ReportRequest.maxNote)
        let noNote = try JSONDecoder().decode(
            JSONValue.self, from: try JSONEncoder().encode(ReportRequest(target: .idea, id: "i1", reason: .spam, note: "   ")))
        #expect(noNote["note"].isNull)
    }

    @Test func test_feedScopesMatchTheContract() {
        #expect(FeedScope.allCases.map(\.rawValue) == ["for_you", "following", "new"])
    }
}
