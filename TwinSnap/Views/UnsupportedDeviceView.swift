//
//  UnsupportedDeviceView.swift
//  TwinSnap
//
//  画面4: MultiCam非対応端末向けガイド。親切なガイド型で対応機種を案内する。
//

import SwiftUI

struct UnsupportedDeviceView: View {

    private let supportedDevices: [String] = [
        "iPhone XS / XS Max / XR",
        "iPhone 11 / 11 Pro / 11 Pro Max",
        "iPhone SE（第2世代以降）",
        "iPhone 12 シリーズ",
        "iPhone 13 シリーズ",
        "iPhone 14 シリーズ",
        "iPhone 15 シリーズ以降"
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "iphone.gen3.slash")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(Color(red: 1.0, green: 0.353, blue: 0.235))
                        .padding(.top, 48)

                    Text("このiPhoneはTwinSnapに対応していません")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Text("TwinSnapは前面と背面のカメラを同時に使う機能（MultiCam）が必要です。この機能は下記の対応機種でのみご利用いただけます。ご不便をおかけして申し訳ありません。")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 32)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("対応機種")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(supportedDevices.enumerated()), id: \.offset) { index, name in
                                HStack {
                                    Text(name)
                                        .font(.body)
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                if index < supportedDevices.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }
            }
        }
    }
}

#Preview {
    UnsupportedDeviceView()
}
