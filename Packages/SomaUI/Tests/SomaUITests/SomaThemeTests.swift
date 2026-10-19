//
//  SomaThemeTests.swift
//  SomaUITests
//

import SwiftUI
import Testing
@testable import SomaUI

@Suite("Theme")
struct SomaThemeTests {
    @Test("A theme compares as one value so SwiftUI can skip an unchanged subtree")
    func themeIsEquatable() {
        #expect(SomaTheme.standard == SomaTheme.standard)
        #expect(SomaTheme.standard != SomaTheme.standard.withAccent(SomaColorValue(0x00FF00)))
    }

    @Test("Swapping the accent leaves the rest of the theme alone")
    func accentSwapIsScoped() {
        let swapped = SomaTheme.standard.withAccent(SomaColorValue(0x00FF00))

        #expect(swapped.colors.accent != SomaTheme.standard.colors.accent)
        #expect(swapped.colors.canvas == SomaTheme.standard.colors.canvas)
        #expect(swapped.typography == SomaTheme.standard.typography)
        #expect(swapped.metrics == SomaTheme.standard.metrics)
    }

    @Test("Danger is its own role, not the accent wearing a different name")
    func dangerIsDistinctFromAccent() {
        let colors = SomaTheme.standard.colors
        #expect(colors.danger != colors.accent)
        #expect(colors.danger != colors.inkPrimary)
        #expect(colors.danger != colors.inkSecondary)
    }

    @Test("Danger reads on both grounds")
    func dangerDiffersLightAndDark() {
        #expect(SomaTheme.standard.colors.danger.light != SomaTheme.standard.colors.danger.dark)
    }

    @Test("Record is its own red, apart from danger, the accent and the inks")
    func recordIsItsOwnRole() {
        let colors = SomaTheme.standard.colors
        #expect(colors.record != colors.danger)
        #expect(colors.record != colors.accent)
        #expect(colors.record != colors.inkPrimary)
        #expect(colors.record != colors.inkSecondary)
    }

    @Test("Record differs between light and dark, as the system red does")
    func recordDiffersLightAndDark() {
        #expect(SomaTheme.standard.colors.record.light != SomaTheme.standard.colors.record.dark)
    }
}

@Suite("Metrics")
struct SomaMetricsTests {
    @Test("Bar height is the tab height plus both insets")
    func barHeightIncludesPadding() {
        let metrics = SomaMetrics(tabHeight: 46, barPadding: 6)
        #expect(metrics.barHeight == 58)
    }

    @Test("A tab is never smaller than the system's minimum touch target")
    func tapTargetFloorHolds() {
        #expect(SomaMetrics.standard.tabHeight >= SomaMetrics.standard.minimumTapTarget)
    }

    @Test("The accessory row is denser once it slides inline beside the bar")
    func inlineAccessoryRowIsDenser() {
        for metrics in [SomaMetrics.touch, SomaMetrics.pointer] {
            #expect(metrics.accessoryRowHeightInline < metrics.accessoryRowHeight)
            #expect(metrics.accessoryRowPaddingInline < metrics.accessoryRowPadding)
            #expect(metrics.accessoryRowSpacingInline < metrics.accessoryRowSpacing)
            #expect(metrics.accessoryMarkDiameterInline < metrics.accessoryMarkDiameter)
        }
    }

    @Test("The inline accessory row still fits a finger on the touch scale")
    func inlineAccessoryRowClearsTouchTarget() {
        #expect(SomaMetrics.touch.accessoryRowHeightInline >= SomaMetrics.touch.minimumTapTarget)
    }

    @Test("The record button's red fits inside its ring", arguments: [SomaMetrics.touch, SomaMetrics.pointer])
    func shutterFits(_ m: SomaMetrics) {
        let inner = m.shutterDiameter - 2 * (m.shutterRingWidth + m.shutterGap)
        #expect(inner > m.shutterStopSide)
        #expect(m.shutterStopCornerRadius * 2 < m.shutterStopSide)
    }

    @Test("The camera's controls meet the touch floor")
    func cameraControlsFitAFinger() {
        let m = SomaMetrics.touch
        #expect(m.cameraControlDiameter >= m.minimumTapTarget)
        #expect(m.shutterDiameter >= m.minimumTapTarget)
    }

    @Test("The desk's camera chrome is tighter than the phone's")
    func pointerCameraIsTighter() {
        #expect(SomaMetrics.pointer.shutterDiameter < SomaMetrics.touch.shutterDiameter)
        #expect(SomaMetrics.pointer.cameraControlDiameter < SomaMetrics.touch.cameraControlDiameter)
        #expect(SomaMetrics.pointer.cameraPillHeight < SomaMetrics.touch.cameraPillHeight)
    }
}



@Suite("Scales")
struct SomaScaleTests {
    @Test("The pointer scale is tighter than the touch scale everywhere it counts")
    func pointerIsDenser() {
        #expect(SomaMetrics.pointer.tabHeight < SomaMetrics.touch.tabHeight)
        #expect(SomaMetrics.pointer.accessoryDiameter < SomaMetrics.touch.accessoryDiameter)
        #expect(SomaMetrics.pointer.accessoryRowHeight < SomaMetrics.touch.accessoryRowHeight)
        #expect(SomaMetrics.pointer.accessoryMarkDiameter < SomaMetrics.touch.accessoryMarkDiameter)
        #expect(SomaTypography.pointer.body.size < SomaTypography.touch.body.size)
        #expect(SomaTypography.pointer.display.size < SomaTypography.touch.display.size)
    }

    @Test("A field reads bigger than body and smaller than the page title")
    func fieldSitsBetweenBodyAndDisplay() {
        for scale in [SomaTypography.touch, SomaTypography.pointer] {
            #expect(scale.field.size > scale.body.size)
            #expect(scale.field.size < scale.display.size)
        }
    }

    @Test("SF Pro is the only family")
    func oneFamily() {
        #expect(SomaFontFamily.allCases == [.pro])
    }

    @Test("Values hold their columns, and words keep the face's own spacing")
    func digitsFollowTheRole() {
        for scale in [SomaTypography.touch, SomaTypography.pointer] {
            #expect(scale.metric.digits == .tabular)
            #expect(scale.rowValue.digits == .tabular)

            let words = [scale.display, scale.title, scale.body, scale.caption,
                         scale.field, scale.tabLabel, scale.eyebrow, scale.segment,
                         scale.headerTitle]
            #expect(words.allSatisfy { $0.digits == .proportional })
        }
    }

    @Test("A tabular role asks SF Pro for tabular digits, a proportional one does not")
    func tabularDigitsReachTheFont() {
        #expect(
            SomaFontSpec(size: 36, digits: .tabular).font
                == Font.system(size: 36, weight: .regular, design: .default).monospacedDigit()
        )
        #expect(
            SomaFontSpec(size: 36).font
                == Font.system(size: 36, weight: .regular, design: .default)
        )
    }

    @Test("Headlines and values are set regular and tight, labels wide, like the site")
    func headlinesAreRegularAndTight() {
        for scale in [SomaTypography.touch, SomaTypography.pointer] {
            for role in [scale.display, scale.title, scale.metric] {
                #expect(role.weight == .regular)
                #expect(role.tracking < 0)
            }
            #expect(scale.eyebrow.tracking > 0)
        }
    }

    @Test("The folded header title reads between a caption and the page title")
    func headerTitleSitsBetweenCaptionAndDisplay() {
        for scale in [SomaTypography.touch, SomaTypography.pointer] {
            #expect(scale.headerTitle.size > scale.caption.size)
            #expect(scale.headerTitle.size < scale.display.size)
            #expect(scale.allRoles.contains(scale.headerTitle))
        }
    }

    @Test("A touch target still clears 44pt on the finger scale")
    func touchClearsAppleMinimum() {
        #expect(SomaMetrics.touch.minimumTapTarget >= 44)
        #expect(SomaMetrics.touch.tabHeight >= 44)
    }

    @Test("A segment label reads between a caption and running text")
    func segmentSitsBetweenCaptionAndBody() {
        for scale in [SomaTypography.touch, SomaTypography.pointer] {
            #expect(scale.segment.size > scale.caption.size)
            #expect(scale.segment.size < scale.body.size)
        }
    }

    @Test("A segmented control's track fits the chrome row it rides in, on both scales")
    func segmentedControlFitsTheChromeRow() {
        for metrics in [SomaMetrics.touch, SomaMetrics.pointer] {
            #expect(metrics.segmentTrackHeight <= metrics.chromeCapsuleHeight)
        }
        #expect(SomaMetrics.pointer.segmentHeight < SomaMetrics.touch.segmentHeight)
    }

    @Test("A segment answers a tap across the smallest touch target, whatever its track draws")
    func segmentReachClearsTheTapFloor() {
        for metrics in [SomaMetrics.touch, SomaMetrics.pointer] {
            #expect(metrics.segmentTrackHeight + metrics.segmentReach * 2 >= metrics.minimumTapTarget)
            #expect(metrics.segmentReach >= 0)
        }
        #expect(SomaMetrics.touch.segmentReach == 3)
    }
}

@Suite("Standard theme")
struct SomaStandardThemeTests {
    @Test("The standard theme wears the site palette and the standard scales")
    func standardIsTheSitePalette() {
        #expect(SomaTheme.standard.colors == SomaColors.standard)
        #expect(SomaTheme.standard.typography == SomaTypography.standard)
        #expect(SomaTheme.standard.metrics == SomaMetrics.standard)
    }

    @Test("A view that sets no theme draws the standard one")
    func environmentDefaultsToStandard() {
        #expect(EnvironmentValues().somaTheme == SomaTheme.standard)
    }

    /// Sixteen on a phone, so cards take the whole width.
    @Test("Phone pages use a narrow gutter, and a hairline is a tenth of the ink")
    func gutterAndHairline() {
        #expect(SomaMetrics.touch.pagePadding == 16)
        #expect(SomaMetrics.touch.hairlineOpacity == 0.10)
        #expect(SomaMetrics.pointer.hairlineOpacity == 0.12)
    }
}
