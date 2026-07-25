import FamilyMediaCore
import SwiftUI

struct MediaCategoryDescriptor: Identifiable, Equatable {
    let title: String
    let subtitle: String
    let systemImage: String
    let filter: MediaFilter
    let accessibilityIdentifier: String

    var id: MediaFilter { filter }

    static let familyMedia: [Self] = [
        Self(
            title: "全部媒体",
            subtitle: "浏览所有照片与视频",
            systemImage: "rectangle.grid.2x2.fill",
            filter: .all,
            accessibilityIdentifier: "media.category.all"
        ),
        Self(
            title: "视频",
            subtitle: "家庭影片与录像",
            systemImage: "video.fill",
            filter: .videos,
            accessibilityIdentifier: "media.category.videos"
        ),
        Self(
            title: "照片",
            subtitle: "照片与珍贵时刻",
            systemImage: "photo.stack.fill",
            filter: .photos,
            accessibilityIdentifier: "media.category.photos"
        )
    ]
}

struct FamilyMediaCategoriesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let source: MediaSourceContext
    let refreshCenter: MediaLibraryRefreshCenter

    var body: some View {
        ZStack {
            AppBackground()
            GeometryReader { proxy in
                let contentWidth = min(
                    max(
                        proxy.size.width
                            - (MediaContentLayoutPolicy.horizontalPadding * 2),
                        0
                    ),
                    FamilyMediaAdaptiveLayout.wideContentMaxWidth
                )
                let layout = MediaContentLayoutPolicy.categoryLayout(
                    availableWidth: contentWidth,
                    horizontalSizeClass: horizontalSizeClass,
                    dynamicTypeSize: dynamicTypeSize
                )

                ScrollView {
                    categoryLayout(layout)
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MediaContentLayoutPolicy.horizontalPadding)
                }
            }
        }
        .navigationTitle("家庭媒体")
        .navigationBarTitleDisplayMode(.inline)
        .familyNavigationStyle()
    }

    @ViewBuilder
    private func categoryLayout(_ layout: MediaCategoryLayout) -> some View {
        switch layout {
        case .singleColumn:
            VStack(spacing: MediaContentLayoutPolicy.spacing) {
                ForEach(MediaCategoryDescriptor.familyMedia) { descriptor in
                    categoryLink(descriptor, usesUniformHeight: false)
                }
            }

        case .featured:
            VStack(spacing: MediaContentLayoutPolicy.spacing) {
                categoryLink(
                    MediaCategoryDescriptor.familyMedia[0],
                    usesUniformHeight: true
                )
                HStack(
                    alignment: .top,
                    spacing: MediaContentLayoutPolicy.spacing
                ) {
                    ForEach(MediaCategoryDescriptor.familyMedia.dropFirst()) { descriptor in
                        categoryLink(descriptor, usesUniformHeight: true)
                    }
                }
            }

        case .threeColumns:
            HStack(
                alignment: .top,
                spacing: MediaContentLayoutPolicy.spacing
            ) {
                ForEach(MediaCategoryDescriptor.familyMedia) { descriptor in
                    categoryLink(descriptor, usesUniformHeight: true)
                }
            }
        }
    }

    private func categoryLink(
        _ descriptor: MediaCategoryDescriptor,
        usesUniformHeight: Bool
    ) -> some View {
        NavigationLink {
            MediaLibraryView(
                title: descriptor.title,
                filter: descriptor.filter,
                source: source,
                refreshCenter: refreshCenter
            )
        } label: {
            GlassCard {
                HStack(spacing: 16) {
                    Image(systemName: descriptor.systemImage)
                        .font(.title2)
                        .foregroundStyle(FamilyMediaTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(
                            FamilyMediaTheme.accent.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(descriptor.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(descriptor.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: usesUniformHeight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: usesUniformHeight
                        ? MediaContentLayoutPolicy.cardMinimumHeight - 36
                        : nil,
                    alignment: .leading
                )
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(descriptor.title)，\(descriptor.subtitle)")
        .accessibilityHint("双击打开")
        .accessibilityIdentifier(descriptor.accessibilityIdentifier)
    }
}
