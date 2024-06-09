import Foundation
import Sessions
#if os(Linux)
import FoundationNetworking
#endif

struct Contributor {
   struct GitHubUser: Codable {
      let id: Int
      let name: String?
      let bio: String?
      let blog: String?
      let twitterUsername: String?
      let avatarUrl: String?
   }

   let githubProfileName: String
   let avatarURL: URL
   let fullName: String
   let shortDescription: String
   let socialLinks: [String: URL]

   init(githubProfileName: String) throws {
      self.githubProfileName = githubProfileName

      let url = URL(string: "https://api.github.com/users/\(githubProfileName)")!

      let data = try Data(contentsOf: url)
      let gitHubUser = try JSONDecoder().decode(GitHubUser.self, from: data)

      self.fullName = gitHubUser.name ?? githubProfileName

      let fullNameTokens = self.fullName.components(separatedBy: .whitespaces)

      if let avatarURLString = gitHubUser.avatarUrl, let avatarURL = URL(string: avatarURLString) {
         self.avatarURL = avatarURL
      } else {
         var urlComponents = URLComponents()
         urlComponents.scheme = "https"
         urlComponents.host = "ui-avatars.com"
         urlComponents.path = "/api/"
         urlComponents.queryItems = [URLQueryItem(name: "name", value: fullNameTokens.joined(separator: "+"))]

         self.avatarURL = urlComponents.url!
      }

      self.shortDescription = gitHubUser.bio ?? "No Bio on GitHub"

      // Fetch social links
      var links = [String: URL]()
      if let blog = gitHubUser.blog, let blogURL = URL(string: blog) {
         links["Blog"] = blogURL
      }
      
      if let twitterUsername = gitHubUser.twitterUsername {
         links["X/Twitter"] = URL(string: "https://x.com/\(twitterUsername)")
      }

      self.socialLinks = links
   }
}

let legalNotes = """

   @Small {
      **Legal Notice**

      All content copyright © 2012 – 2024 Apple Inc. All rights reserved.
      Swift, the Swift logo, Swift Playgrounds, Xcode, Instruments, Cocoa Touch, Touch ID, FaceID, iPhone, iPad, Safari, Apple Vision, Apple Watch, App Store, iPadOS, watchOS, visionOS, tvOS, Mac, and macOS are trademarks of Apple Inc., registered in the U.S. and other countries.
      This website is not made by, affiliated with, nor endorsed by Apple.
   }
   """

let sessionByID = try Session.allSessionsByID()

let events = ["WWDC23"]

var contributorsByProfile: [String: Contributor] = [:]
var sessionIDsWithoutContributors: Set<String> = []
var sessionIDsByProfile: [String: Set<String>] = [:]


// MARK: - Append 'Written by' section, Related Sessions section, and Legal Footer to all Notes

for event in events {
   let eventSessionsPath = "\(FileManager.default.currentDirectoryPath)/Sources/WWDCNotes/WWDCNotes.docc/\(event)"
   let sessionFileNames = try FileManager.default.contentsOfDirectory(atPath: eventSessionsPath).filter { $0.hasSuffix(".md") }

   let contributorRegex = try Regex(#"@GitHubUser\(([^\n<>]+)\)"#)

   for sessionFileName in sessionFileNames {
      if let session = sessionByID.values.first(where: { $0.fileName.lowercased() + ".md" == sessionFileName.lowercased() }) {
         let sessionFilePath = "\(eventSessionsPath)/\(sessionFileName)"
         var sessionFileContents = try String(contentsOfFile: sessionFilePath, encoding: .utf8)

         let sessionContributorNames = sessionFileContents.matches(of: contributorRegex).compactMap { $0[1].substring }.map(String.init)
         if sessionContributorNames.isEmpty {
            sessionIDsWithoutContributors.insert(session.id)
         }
         
         let sessionContributors = try sessionContributorNames.map { profile in
            sessionIDsByProfile[profile, default: []].insert(session.id)

            if let existingContributor = contributorsByProfile[profile] {
               return existingContributor
            } else {
               let newContributor = try Contributor(githubProfileName: profile)
               contributorsByProfile[profile] = newContributor
               return newContributor
            }
         }

         if !sessionContributors.isEmpty {
            sessionFileContents += "\n\n## Written By\n"
            for contributor in sessionContributors {
               sessionFileContents += """

                  @Row(numberOfColumns: 5) {
                     @Column { ![Profile image of \(contributor.fullName)](\(contributor.avatarURL.absoluteString) }
                     @Column(size: 4) {
                        ### [\(contributor.fullName)](<doc:\(contributor.githubProfileName)>)

                        [Contributed Notes](<doc:\(contributor.githubProfileName)>)
                  \(contributor.socialLinks.map { "      [\($0)](\($1.absoluteString))" }.joined(separator: "\n"))
                     }
                  }

                  """
            }
         }

         if !session.relatedSessionIDs.isEmpty {
            sessionFileContents += """


               ## Related Sessions

               @Links(visualStyle: list) {

               """

            for relatedSessionID in session.relatedSessionIDs {
               if let relatedSession = sessionByID[relatedSessionID] {
                  sessionFileContents += "   - <doc:\(relatedSession.fileName)>\n"
               }
            }

            sessionFileContents += "}\n\n"
         }

         sessionFileContents += legalNotes

         try sessionFileContents.write(toFile: sessionFilePath, atomically: true, encoding: .utf8)
      }
   }
}


// MARK: - Generate all Contributor/<Profile>.md

let contributorsPath = "\(FileManager.default.currentDirectoryPath)/Sources/WWDCNotes/WWDCNotes.docc/Contributors"
try FileManager.default.createDirectory(atPath: contributorsPath, withIntermediateDirectories: true)

for contributor in contributorsByProfile.values {
   guard let contributedSessionsIDs = sessionIDsByProfile[contributor.githubProfileName] else { continue }
   let contributedSessions = contributedSessionsIDs.compactMap { sessionByID[$0] }
   let contributedSessionByYear = Dictionary(grouping: contributedSessions, by: \.year)

   let mostActiveYear = contributedSessionByYear.max { $0.value.count > $1.value.count }?.key ?? 0

   let contributorFilePath = "\(contributorsPath)/\(contributor.githubProfileName).md"
   var contributorFileContents = """
      # \(contributor.fullName) (\(contributedSessions.count) \(contributedSessions.count > 1 ? "notes" : "note"))

      \(contributor.shortDescription)

      @Metadata {
         @TitleHeading("Contributors")
         @PageKind(sampleCode)
      }

      ## About

      @Row(numberOfColumns: 5) {
         @Column { ![Profile image of \(contributor.fullName)](\(contributor.avatarURL.absoluteString)) }
         @Column(size: 4) {
            ### [\(contributor.fullName)](<doc:\(contributor.githubProfileName)>)

            \(contributor.socialLinks.map { "      [\($0)](\($1.absoluteString))" }.joined(separator: "\n"))
         }
      }

      ## Contributions

      Contributed \(contributedSessions.count) session \(contributedSessions.count > 1 ? "notes" : "note") in total. Their most active year was \(mostActiveYear).

      """

   for (year, sessionsInYear) in contributedSessionByYear {
      contributorFileContents += """

         ### \(year)

         @Links(visualStyle: list) {
         \(sessionsInYear.map { "   - <doc:\($0.fileName)>" }.joined(separator: "\n"))
         }

         """
   }

   try contributorFileContents.write(toFile: contributorFilePath, atomically: true, encoding: .utf8)
}


// MARK: - Generate Contributors.md

let contributorsOverviewFilePath = "\(FileManager.default.currentDirectoryPath)/Sources/WWDCNotes/WWDCNotes.docc/Contributors.md"
var contributorsOverviewContents = """
   # Contributors

   WWDCNotes is only possible thanks to these awesome volunteers! Contribute now to get listed here as well.

   @Metadata {
      @TitleHeading("Overview")
      @PageKind(article)
      @CallToAction(url: "/documentation/wwdcnotes/contributing", purpose: link, label: "Become a Contributor")
   }

   ## Topics

   Here's a full list of all \(sessionIDsByProfile.keys.count) people who contributed to WWDCNotes – sorted by most contributions.

   \(sessionIDsByProfile.sorted { $0.value.count > $1.value.count }.map { "- <doc:\($0.key)>" }.joined(separator: "\n"))

   """

contributorsOverviewContents += legalNotes

try contributorsOverviewContents.write(toFile: contributorsOverviewFilePath, atomically: true, encoding: .utf8)


// MARK: - Generate MissingNotes.md

let sessionsWithoutContributorsByYear = Dictionary(grouping: sessionIDsWithoutContributors.compactMap { sessionByID[$0] }, by: \.year)

let missingNotesFilePath = "\(FileManager.default.currentDirectoryPath)/Sources/WWDCNotes/WWDCNotes.docc/MissingNotes.md"
var missingNotesContents = """
   # Missing Sessions

   This page gives you an overview of all sessions that have no notes yet. Many opportunities to contribute!

   
   """

for (year, sessions) in sessionsWithoutContributorsByYear {
   missingNotesContents += """

      ## WWDC\(year - 2000)

      @Links(visualStyle: list) {
      \(sessions.map { "   - <doc:\($0.fileName)>" }.joined(separator: "\n"))
      }

      """
}

try missingNotesContents.write(toFile: missingNotesFilePath, atomically: true, encoding: .utf8)


// MARK: - Generate WWDC year overview page contents

let years = Set(sessionByID.values.map(\.year))

for year in years {
   let eventName = "WWDC\(year - 2000)"
   let yearOverviewFilePath = "\(FileManager.default.currentDirectoryPath)/Sources/WWDCNotes/WWDCNotes.docc/\(eventName).md"
   var yearOverviewFileContents = try String(contentsOfFile: yearOverviewFilePath)

   let yearSessions = sessionByID.values.filter { $0.year == year }.sorted { $0.title < $1.title }

   let firstDayEventSessions = yearSessions.filter { $0.title.lowercased() == "keynote" || $0.title.lowercased() == "platforms state of the union" }
   yearOverviewFileContents += """


      ## Topics

      ### First Day Events

      @Links(visualStyle: list) {
      \(firstDayEventSessions.map { "   - <doc:\($0.fileName)>" }.joined(separator: "\n"))
      }

      """

   let newToolAndFrameworkSessions = yearSessions.filter { session in
      session.title.lowercased().starts(with: "meet ") || session.title.lowercased().starts(with: "introducing ")
   }
   yearOverviewFileContents += """
      
      ### New Tools & Frameworks

      @Links(visualStyle: list) {
      \(newToolAndFrameworkSessions.map { "   - <doc:\($0.fileName)>" }.joined(separator: "\n"))
      }

      """

   let updatedToolAndFrameworkSessions = yearSessions.filter { session in
      session.title.lowercased().replacing("'", with: "").replacing("’", with: "").starts(with: "whats new in ")
   }
   yearOverviewFileContents += """

      ### Updated Tools & Frameworks

      @Links(visualStyle: list) {
      \(updatedToolAndFrameworkSessions.map { "   - <doc:\($0.fileName)>" }.joined(separator: "\n"))
      }

      """

   let otherSessions = yearSessions.filter { !(firstDayEventSessions + newToolAndFrameworkSessions + updatedToolAndFrameworkSessions).map(\.id).contains($0.id) }
   yearOverviewFileContents += """

      ### Deep Dives into Topics

      @Links(visualStyle: list) {
      \(otherSessions.map { "   - <doc:\($0.fileName)>" }.joined(separator: "\n"))
      }

      """

   try yearOverviewFileContents.write(toFile: yearOverviewFilePath, atomically: true, encoding: .utf8)
}