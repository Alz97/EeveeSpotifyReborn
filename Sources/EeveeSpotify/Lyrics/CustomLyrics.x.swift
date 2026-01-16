// CustomLyrics.x.swift
import Orion
import SwiftUI

//

struct BaseLyricsGroup: HookGroup { }

struct LegacyLyricsGroup: HookGroup { }
struct ModernLyricsGroup: HookGroup { }
struct V91LyricsGroup: HookGroup { }  // For Spotify 9.1.x - excludes incompatible hooks
struct LyricsErrorHandlingGroup: HookGroup { }  // ErrorViewController hooks - not compatible with 9.1.x

var lyricsState = LyricsLoadingState()

var hasShownRestrictedPopUp = false
var hasShownUnauthorizedPopUp = false

var capturedTrackId: String?
var capturedTrackTitle: String?
var capturedArtistName: String?

private let geniusLyricsRepository = GeniusLyricsRepository()
private let petitLyricsRepository = PetitLyricsRepository()

// Overload for 9.1.x where we only have track ID from URL
private func loadCustomLyricsForTrackId(_ trackId: String) throws -> Lyrics {
    
    let source = UserDefaults.lyricsSource
    
    // Check if we have captured metadata from the UI hooks
    // NOTA: Queste variabili sono dichiarate in V91TrackMetadataCapture.x.swift
    let hasMetadata = capturedTrackId == trackId && capturedTrackTitle != nil && capturedArtistName != nil
    
    // For 9.1.x: Genius/LRCLIB/Petit need track title/artist
    // They will only work if we have captured metadata
    let needsMetadata = source == .genius || source == .lrclib || source == .petit
    
    if needsMetadata && !hasMetadata {
        throw LyricsError.noSuchSong
    }
    
    // Create search query with available data
    let searchQuery = LyricsSearchQuery(
        title: capturedTrackTitle ?? "",
        primaryArtist: capturedArtistName ?? "",
        spotifyTrackId: trackId
    )
    
    let options = UserDefaults.lyricsOptions
    
    var repository: LyricsRepository

    switch source {
    case .genius:
        repository = geniusLyricsRepository
    case .lrclib:
        repository = LrclibLyricsRepository.shared
    case .musixmatch:
        repository = MusixmatchLyricsRepository.shared
    case .petit:
        repository = petitLyricsRepository
    case .notReplaced:
        throw LyricsError.invalidSource
    }
    
    let lyricsDto: LyricsDto
    
    lyricsState = LyricsLoadingState()
    
    do {
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
    }
    catch let error {
        throw error
    }
    
    lyricsState.isEmpty = lyricsDto.lines.isEmpty
    
    lyricsState.wasRomanized = lyricsDto.romanization == .romanized
        || (lyricsDto.romanization == .canBeRomanized && UserDefaults.lyricsOptions.romanization)
    
    lyricsState.loadedSuccessfully = true

    let lyrics = Lyrics.with {
        $0.data = lyricsDto.toSpotifyLyricsData(source: source.description)
    }
    
    return lyrics
}

private func loadCustomLyricsForCurrentTrack() throws -> Lyrics {
    
    // For 9.1.x versions, use the track ID-based approach
    if EeveeSpotify.hookTarget == .v91 {
        guard let trackId = capturedTrackId else {
            throw LyricsError.noCurrentTrack
        }
        return try loadCustomLyricsForTrackId(trackId)
    }
    
    guard
        let track = statefulPlayer?.currentTrack() ??
                    nowPlayingScrollViewController?.loadedTrack
        else {
            throw LyricsError.noCurrentTrack
        }
    
    let trackTitle = track.trackTitle()
    let artistName = EeveeSpotify.hookTarget == .lastAvailableiOS14
        ? track.artistTitle()
        : track.artistName()
    
    let searchQuery = LyricsSearchQuery(
        title: trackTitle,
        primaryArtist: artistName,
        spotifyTrackId: track.trackIdentifier
    )
    
    let options = UserDefaults.lyricsOptions
    var source = UserDefaults.lyricsSource
    
    var repository: LyricsRepository

    switch source {
    case .genius:
        repository = geniusLyricsRepository
    case .lrclib:
        repository = LrclibLyricsRepository.shared
    case .musixmatch:
        repository = MusixmatchLyricsRepository.shared
    case .petit:
        repository = petitLyricsRepository
    case .notReplaced:
        throw LyricsError.invalidSource
    }
    
    let lyricsDto: LyricsDto
    
    lyricsState = LyricsLoadingState()
    
    do {
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
    }
    catch let error {
        if let error = error as? LyricsError {
            lyricsState.fallbackError = error
            
            switch error {
                
            case .invalidMusixmatchToken:
                if !hasShownUnauthorizedPopUp {
                    PopUpHelper.showPopUp(
                        delayed: false,
                        message: "musixmatch_unauthorized_popup".localized,
                        buttonText: "OK".uiKitLocalized
                    )
                    
                    hasShownUnauthorizedPopUp.toggle()
                }
            
            case .musixmatchRestricted:
                if !hasShownRestrictedPopUp {
                    PopUpHelper.showPopUp(
                        delayed: false,
                        message: "musixmatch_restricted_popup".localized,
                        buttonText: "OK".uiKitLocalized
                    )
                    
                    hasShownRestrictedPopUp.toggle()
                }
                
            default:
                break
            }
        }
        else {
            lyricsState.fallbackError = .unknownError
        }
        
        if source == .genius || !UserDefaults.lyricsOptions.geniusFallback {
            throw error
        }
        
        source = .genius
        repository = GeniusLyricsRepository()
        
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
    }
    
    lyricsState.isEmpty = lyricsDto.lines.isEmpty
    
    lyricsState.wasRomanized = lyricsDto.romanization == .romanized
        || (lyricsDto.romanization == .canBeRomanized && UserDefaults.lyricsOptions.romanization)
    
    lyricsState.loadedSuccessfully = true

    let lyrics = Lyrics.with {
        $0.data = lyricsDto.toSpotifyLyricsData(source: source.description)
    }
    
    return lyrics
}

func getLyricsDataForCurrentTrack(_ originalPath: String, originalLyrics: Lyrics? = nil) throws -> Data {
    
    // For 9.1.x versions, extract track ID from URL and use capture system
    if EeveeSpotify.hookTarget == .v91 {
        // Extract track ID from URL path since player objects are nil in 9.1.x
        // Format: /color-lyrics/v2/track/{trackId} or /lyrics/.../{trackId}
        let trackIdentifier: String
        if let range = originalPath.range(of: #"/track/([a-zA-Z0-9]+)"#, options: .regularExpression) {
            let match = originalPath[range]
            trackIdentifier = String(match.split(separator: "/").last ?? "")
        } else {
            throw LyricsError.noCurrentTrack
        }
        
        // Verify track ID was extracted
        if trackIdentifier.isEmpty {
            throw LyricsError.noCurrentTrack
        }
        
        // Try to capture metadata from view hierarchy at lyrics request time
        // Always try to capture fresh metadata when track changes
        // Clear old metadata if track ID changed
        if capturedTrackId != trackIdentifier {
            capturedTrackTitle = nil
            capturedArtistName = nil
            capturedTrackId = nil
            
            // Delay to let Now Playing UI fully update before capturing
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        // 1. Try MPNowPlayingInfoCenter first (System info)
        var info: (title: String?, artist: String?)? = getSystemNowPlayingInfo()
        
        // 2. Fallback to view hierarchy scraping if system info failed
        if info == nil {
            info = searchViewHierarchyForTrackInfo()
        }

        if let info = info {
            capturedTrackTitle = info.title
            capturedArtistName = info.artist
            capturedTrackId = trackIdentifier
        } else {
            // Keep old metadata if we fail to capture new - better than nothing
        }
        
        // Use track ID version for 9.1.x where we don't have track objects
        var lyrics = try loadCustomLyricsForTrackId(trackIdentifier)
        
        let lyricsColorsSettings = UserDefaults.lyricsColors
        
        if lyricsColorsSettings.displayOriginalColors, let originalLyrics = originalLyrics {
            lyrics.colors = originalLyrics.colors
        }
        else {
            // For 9.1.x, we don't have track object to extract color from
            // Use static color if enabled, otherwise use background color or gray
            var color: Color
            
            if lyricsColorsSettings.useStaticColor {
                color = Color(hex: lyricsColorsSettings.staticColor)
            }
            else if let uiColor = backgroundViewModel?.color() {
                color = Color(uiColor)
                    .normalized(lyricsColorsSettings.normalizationFactor)
            }
            else {
                color = Color.gray
            }
            
            lyrics.colors = LyricsColors.with {
                $0.backgroundColor = color.uInt32
                $0.lineColor = Color.black.uInt32
                $0.activeLineColor = Color.white.uInt32
            }
        }
        
        let serializedData = try lyrics.serializedData()
        return serializedData
    }
    
    // Original logic for non-9.1.x versions
    guard
        let track = statefulPlayer?.currentTrack() ??
                    nowPlayingScrollViewController?.loadedTrack
        else {
            throw LyricsError.noCurrentTrack
        }
    
    let trackIdentifier = track.trackIdentifier
    
    if !trackIdentifier.isEmpty && !originalPath.contains(trackIdentifier) {
        throw LyricsError.trackMismatch
    }
    
    var lyrics = try loadCustomLyricsForCurrentTrack()
    
    let lyricsColorsSettings = UserDefaults.lyricsColors
    
    if lyricsColorsSettings.displayOriginalColors, let originalLyrics = originalLyrics {
        lyrics.colors = originalLyrics.colors
    }
    else {
        let extractedColor = switch EeveeSpotify.hookTarget {
        case .lastAvailableiOS14:
            track.extractedColorHex()
        default:
            track.metadata()["extracted_color"]
        }
        
        var color: Color
        
        if lyricsColorsSettings.useStaticColor {
            color = Color(hex: lyricsColorsSettings.staticColor)
        }
        else if let extractedColor = extractedColor {
            color = Color(hex: extractedColor)
                .normalized(lyricsColorsSettings.normalizationFactor)
        }
        else if let uiColor = backgroundViewModel?.color() {
            color = Color(uiColor)
                .normalized(lyricsColorsSettings.normalizationFactor)
        }
        else {
            color = Color.gray
        }
        
        lyrics.colors = LyricsColors.with {
            $0.backgroundColor = color.uInt32
            $0.lineColor = Color.black.uInt32
            $0.activeLineColor = Color.white.uInt32
        }
    }
    
    return try lyrics.serializedBytes()
}
