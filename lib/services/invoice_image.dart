import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../core/jalali.dart';
import '../models/invoice.dart';

/// Generates a polished, receipt-style invoice PNG from *historical*
/// invoice data — the exact snapshot prices stored when the invoice was
/// created. Rendered with the bundled Vazirmatn font so it looks identical
/// on every device, then handed to the Android share sheet.
class InvoiceImageGenerator {
  static const double pageW = 1080;

  Future<String> generate({
    required Invoice invoice,
    required String storeName,
    required String storePhone,
    required String storeAddress,
    required String currencyLabel,
    required String? logoRelativePath,
    required String? logoDocsDirPath,
    required ui.Color accent,
  }) async {
    const margin = 56.0;
    final contentW = pageW - margin * 2;
    const ink = ui.Color(0xFF101828);
    const muted = ui.Color(0xFF667085);
    const soft = ui.Color(0xFFF3F6F5);
    const lineC = ui.Color(0xFFE4EAE8);

    ui.Image? logo;
    if (logoRelativePath != null && logoDocsDirPath != null) {
      try {
        final bytes = await File(
                p.join(logoDocsDirPath, logoRelativePath))
            .readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 300);
        final frame = await codec.getNextFrame();
        logo = frame.image;
      } catch (_) {
        logo = null;
      }
    }

    ui.Paragraph para(
      String text, {
      required double size,
      ui.FontWeight weight = ui.FontWeight.w400,
      required ui.Color color,
      ui.TextAlign align = ui.TextAlign.right,
      double lineHeight = 1.5,
      double? width,
      int maxLines = 1,
    }) {
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontFamily: 'Vazirmatn',
          fontSize: size,
          fontWeight: weight,
          textAlign: align,
          textDirection: ui.TextDirection.rtl,
          height: lineHeight,
          maxLines: maxLines,
        ),
      );
      pb.pushStyle(ui.TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        fontFamily: 'Vazirmatn',
      ));
      pb.addText(text);
      return pb.build()
        ..layout(ui.ParagraphConstraints(width: width ?? contentW));
    }

    final els = <(double, void Function(ui.Canvas, double))>[];

    // ---- top accent bar
    els.add((
      14,
      (c, y) {
        c.drawRect(
          ui.Rect.fromLTWH(0, 0, pageW, 14),
          ui.Paint()..color = accent,
        );
      }
    ));

    // ---- header: logo + store name + contact
    final safeName = storeName.trim().isEmpty ? 'فروشگاه من' : storeName.trim();
    final nameP = para(safeName,
        size: 52,
        weight: ui.FontWeight.w800,
        color: ink,
        width: contentW - 160);
    final contact = [storePhone.trim(), storeAddress.trim()]
        .where((s) => s.isNotEmpty)
        .join('   •   ');
    final contactP = contact.isEmpty
        ? null
        : para(contact, size: 27, color: muted, width: contentW - 160);
    final headerH = 34 +
        nameP.height +
        (contactP == null ? 0 : contactP.height + 10) +
        30;
    els.add((headerH, (c, y) {
      const logoSize = 132.0;
      final lx = pageW - margin - logoSize;
      final ly = y + 30;
      if (logo != null) {
        c.save();
        c.clipPath(
            ui.Path()..addOval(ui.Rect.fromLTWH(lx, ly, logoSize, logoSize)));
        final lw = logo.width.toDouble();
        final lh = logo.height.toDouble();
        var sw = lw, sh = lh, dx = 0.0, dy = 0.0;
        if (lw > lh) {
          sw = lh;
          dx = (lw - lh) / 2;
        } else {
          sh = lw;
          dy = (lh - lw) / 2;
        }
        c.drawImageRect(
          logo,
          ui.Rect.fromLTWH(dx, dy, sw, sh),
          ui.Rect.fromLTWH(lx, ly, logoSize, logoSize),
          ui.Paint(),
        );
        c.restore();
      } else {
        c.drawCircle(
          ui.Offset(lx + logoSize / 2, ly + logoSize / 2),
          logoSize / 2,
          ui.Paint()..color = accent.withValues(alpha: 0.13),
        );
        final firstChar = String.fromCharCode(
            safeName.runes.isEmpty ? 0x3F : safeName.runes.first);
        final initP = para(
          firstChar,
          size: 54,
          weight: ui.FontWeight.w800,
          color: accent,
          align: ui.TextAlign.center,
          width: logoSize,
        );
        c.drawParagraph(
            initP, ui.Offset(lx, ly + logoSize / 2 - initP.height / 2));
      }
      c.drawParagraph(nameP, ui.Offset(margin, y + 34));
      if (contactP != null) {
        c.drawParagraph(
            contactP, ui.Offset(margin, y + 34 + nameP.height + 10));
      }
    }));

    // ---- divider
    els.add((34, (c, y) {
      c.drawRect(ui.Rect.fromLTWH(margin, y + 16, contentW, 2),
          ui.Paint()..color = lineC);
    }));

    // ---- info boxes: invoice number / date / status / customer
    final jdt = jalaliFromDateTime(invoice.createdAt);
    final dateStr = toPersianDigits(
        '${jdt.year}/${jdt.month.toString().padLeft(2, '0')}/${jdt.day.toString().padLeft(2, '0')}');
    final statusInk = invoice.status == InvoiceStatus.paid
        ? const ui.Color(0xFF2E7D32)
        : const ui.Color(0xFFB45309);
    final boxW = (contentW - 48) / 4;
    final boxData = <(String, String, ui.Color?)>[
      ('شماره فاکتور', toPersianDigits('${invoice.number}'), null),
      ('تاریخ', dateStr, null),
      ('وضعیت پرداخت', invoice.status.faLabel, statusInk),
      (
        'مشتری',
        invoice.customerName.trim().isEmpty
            ? 'مشتری ناشناس'
            : invoice.customerName.trim(),
        null,
      ),
    ];
    const infoH = 152.0;
    els.add((infoH, (c, y) {
      for (var i = 0; i < 4; i++) {
        final bx = pageW - margin - (i + 1) * boxW - i * 16;
        c.drawRRect(
          ui.RRect.fromRectAndRadius(
              ui.Rect.fromLTWH(bx, y, boxW, infoH - 24),
              const ui.Radius.circular(18)),
          ui.Paint()..color = soft,
        );
        final lp = para(boxData[i].$1,
            size: 22, color: muted, width: boxW - 28);
        final vp = para(boxData[i].$2,
            size: 28,
            weight: ui.FontWeight.w700,
            color: boxData[i].$3 ?? ink,
            width: boxW - 28,
            maxLines: 1);
        c.drawParagraph(lp, ui.Offset(bx + 14, y + 22));
        c.drawParagraph(vp, ui.Offset(bx + 14, y + 22 + lp.height + 8));
      }
    }));

    // ---- table header (RTL columns: name | qty | unit | total)
    final nameW = contentW * 0.40;
    final qtyW = contentW * 0.14;
    final unitW = contentW * 0.21;
    final totalW = contentW * 0.25;
    const headH = 64.0;
    els.add((headH + 10, (c, y) {
      c.drawRRect(
        ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(margin, y, contentW, headH),
            const ui.Radius.circular(14)),
        ui.Paint()..color = soft,
      );
      final cols = <(String, double, ui.TextAlign)>[
        ('کالا', nameW, ui.TextAlign.right),
        ('تعداد', qtyW, ui.TextAlign.center),
        ('قیمت واحد', unitW, ui.TextAlign.center),
        ('جمع', totalW, ui.TextAlign.center),
      ];
      var xr = pageW - margin;
      for (final col in cols) {
        final hp = para(col.$1,
            size: 25,
            weight: ui.FontWeight.w700,
            color: muted,
            align: col.$3,
            width: col.$2);
        c.drawParagraph(
            hp, ui.Offset(xr - col.$2, y + (headH - hp.height) / 2));
        xr -= col.$2;
      }
    }));

    // ---- item rows
    for (var i = 0; i < invoice.items.length; i++) {
      final it = invoice.items[i];
      final isLast = i == invoice.items.length - 1;
      final nameP = para(it.productName,
          size: 31,
          weight: ui.FontWeight.w700,
          color: ink,
          width: nameW,
          maxLines: 2);
      final subParts = <String>[
        'سایز ${it.variantName}',
        if (it.productColor.isNotEmpty) 'رنگ ${it.productColor}',
      ];
      final subP = para(subParts.join('  •  '),
          size: 24, color: muted, width: nameW, maxLines: 1);
      final qtyP = para(toPersianDigits('${it.quantity}'),
          size: 29,
          color: ink,
          align: ui.TextAlign.center,
          width: qtyW);
      final unitP = para(moneyText(it.unitPrice, currencyLabel),
          size: 25, color: muted, align: ui.TextAlign.center, width: unitW);
      final totalP = para(moneyText(it.total, currencyLabel),
          size: 28,
          weight: ui.FontWeight.w700,
          color: ink,
          align: ui.TextAlign.center,
          width: totalW);
      final rowH = 22 + nameP.height + 6 + subP.height + 22;
      els.add((rowH, (c, y) {
        c.drawParagraph(
            nameP, ui.Offset(pageW - margin - nameW, y + 22));
        c.drawParagraph(subP,
            ui.Offset(pageW - margin - nameW, y + 22 + nameP.height + 6));
        c.drawParagraph(qtyP,
            ui.Offset(pageW - margin - nameW - qtyW, y + (rowH - qtyP.height) / 2));
        c.drawParagraph(
            unitP,
            ui.Offset(pageW - margin - nameW - qtyW - unitW,
                y + (rowH - unitP.height) / 2));
        c.drawParagraph(
            totalP, ui.Offset(margin, y + (rowH - totalP.height) / 2));
        if (!isLast) {
          c.drawRect(ui.Rect.fromLTWH(margin, y + rowH - 1, contentW, 1),
              ui.Paint()..color = lineC);
        }
      }));
    }

    // ---- optional description block (skipped entirely when empty so it
    // occupies no space). Always the historical description of the invoice.
    final descText = invoice.description.trim();
    if (descText.isNotEmpty) {
      final dLabelP = para('توضیحات',
          size: 24,
          weight: ui.FontWeight.w700,
          color: muted,
          width: contentW - 48);
      final dBodyP = para(descText,
          size: 26,
          color: ink,
          width: contentW - 48,
          maxLines: 10,
          lineHeight: 1.7);
      final dH = 22 + dLabelP.height + 8 + dBodyP.height + 24;
      els.add((dH, (c, y) {
        c.drawRRect(
          ui.RRect.fromRectAndRadius(
              ui.Rect.fromLTWH(margin, y, contentW, dH - 8),
              const ui.Radius.circular(18)),
          ui.Paint()..color = soft,
        );
        c.drawParagraph(dLabelP, ui.Offset(margin + 24, y + 20));
        c.drawParagraph(
            dBodyP, ui.Offset(margin + 24, y + 20 + dLabelP.height + 8));
      }));
    }

    // ---- total band
    final totalLabel = para('جمع کل',
        size: 33, weight: ui.FontWeight.w700, color: ink, width: 300);
    final totalVal = para(moneyText(invoice.total, currencyLabel),
        size: 44,
        weight: ui.FontWeight.w800,
        color: accent,
        align: ui.TextAlign.left,
        width: contentW - 340);
    final labelH = totalVal.height > totalLabel.height
        ? totalVal.height
        : totalLabel.height;
    final bandH = 30 + labelH + 30;
    els.add((bandH, (c, y) {
      c.drawRRect(
        ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(margin, y, contentW, bandH - 8),
            const ui.Radius.circular(20)),
        ui.Paint()..color = accent.withValues(alpha: 0.09),
      );
      c.drawParagraph(totalLabel,
          ui.Offset(pageW - margin - 24 - 300, y + (bandH - 8 - totalLabel.height) / 2));
      c.drawParagraph(totalVal,
          ui.Offset(margin + 24, y + (bandH - 8 - totalVal.height) / 2));
    }));

    // ---- footer
    final thanksP = para('با تشکر از اعتماد شما',
        size: 29,
        weight: ui.FontWeight.w600,
        color: ink,
        align: ui.TextAlign.center);
    final footerContact = [storePhone.trim(), storeAddress.trim()]
        .where((s) => s.isNotEmpty)
        .join('   •   ');
    final fcP = footerContact.isEmpty
        ? null
        : para(footerContact, size: 25, color: muted, align: ui.TextAlign.center);
    final wmP = para('صادرشده با LocStore',
        size: 22, color: muted, align: ui.TextAlign.center);
    final footerH = 46 +
        thanksP.height +
        (fcP == null ? 0 : fcP.height + 8) +
        10 +
        wmP.height +
        10;
    els.add((footerH, (c, y) {
      c.drawRect(ui.Rect.fromLTWH(margin, y + 22, contentW, 2),
          ui.Paint()..color = lineC);
      var fy = y + 46;
      c.drawParagraph(thanksP, ui.Offset(margin, fy));
      fy += thanksP.height + 8;
      if (fcP != null) {
        c.drawParagraph(fcP, ui.Offset(margin, fy));
        fy += fcP.height + 8;
      }
      c.drawParagraph(wmP, ui.Offset(margin, fy));
    }));

    // ---- measure page height, then paint
    var pageH = 40.0;
    for (final e in els) {
      pageH += e.$1;
    }
    pageH += 24;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pageW, pageH),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    var y = 40.0;
    for (final e in els) {
      e.$2(canvas, y);
      y += e.$1;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pageW.toInt(), pageH.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('image encode failed');
    final tmp = await getTemporaryDirectory();
    final out = File(p.join(tmp.path, 'locstore-invoice-${invoice.number}.png'));
    await out.writeAsBytes(data.buffer.asUint8List());
    return out.path;
  }
}
