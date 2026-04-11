import SwiftUI

struct FlowLayout: Layout {
  var horizontalSpacing: CGFloat = 8
  var verticalSpacing: CGFloat = 8

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .greatestFiniteMagnitude
    let rows = arrangeRows(maxWidth: maxWidth, subviews: subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.last.map { $0.yOffset + $0.height } ?? 0
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let rows = arrangeRows(maxWidth: bounds.width, subviews: subviews)
    for row in rows {
      for item in row.items {
        let point = CGPoint(
          x: bounds.minX + item.xOffset,
          y: bounds.minY + row.yOffset
        )
        subviews[item.index].place(
          at: point,
          anchor: .topLeading,
          proposal: ProposedViewSize(item.size)
        )
      }
    }
  }

  private func arrangeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var currentItems: [RowItem] = []
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var rowHeight: CGFloat = 0
    var rowWidth: CGFloat = 0

    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let itemWidth = min(size.width, maxWidth)
      let spacing = currentItems.isEmpty ? CGFloat.zero : horizontalSpacing

      if !currentItems.isEmpty && currentX + spacing + itemWidth > maxWidth {
        rows.append(
          Row(
            items: currentItems,
            width: rowWidth,
            height: rowHeight,
            yOffset: currentY
          )
        )
        currentY += rowHeight + verticalSpacing
        currentItems = []
        currentX = 0
        rowHeight = 0
        rowWidth = 0
      }

      let xOffset = currentItems.isEmpty ? CGFloat.zero : currentX + horizontalSpacing
      currentItems.append(
        RowItem(index: index, size: CGSize(width: itemWidth, height: size.height), xOffset: xOffset)
      )
      currentX = xOffset + itemWidth
      rowWidth = currentX
      rowHeight = max(rowHeight, size.height)
    }

    if !currentItems.isEmpty {
      rows.append(
        Row(
          items: currentItems,
          width: rowWidth,
          height: rowHeight,
          yOffset: currentY
        )
      )
    }

    return rows
  }
}

private struct Row {
  let items: [RowItem]
  let width: CGFloat
  let height: CGFloat
  let yOffset: CGFloat
}

private struct RowItem {
  let index: Int
  let size: CGSize
  let xOffset: CGFloat
}
