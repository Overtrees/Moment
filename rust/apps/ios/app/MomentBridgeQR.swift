// ── 配对二维码生成（桥设置待配对卡）──
// 纯函数：把配对页 URL 编成二维码图。载荷口径
// 见 docs/reports/impl_pairing_qr.md：输入只许是
// BridgeCoordinator.pairingURL() 的逐字输出
// （公开寻址量两项），本文件不接触任何凭据材
// 料（verify B16-QR-2 以 grep 锁零出现）。生
// 成侧整数倍放大保证模块边缘锐利，视图层只
// 定边长、不另做缩放处理。

import CoreImage
import UIKit

/// 配对页 URL → 二维码图（纠错级 M）。
func makePairingQRImage(_ urlString: String) -> UIImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator")
    else { return nil }
    filter.setValue(Data(urlString.utf8),
                    forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else {
        return nil
    }
    let scaled = output.transformed(
        by: CGAffineTransform(scaleX: 8, y: 8))
    guard let cg = CIContext().createCGImage(
        scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}
