platform :ios, '9.0'

target 'TrustKeystore' do
  use_frameworks!
  pod 'BigInt', '~> 3.0'
  pod 'CryptoSwift', '~> 1.0'
  pod 'secp256k1_ios', git: 'https://github.com/shamatar/secp256k1_ios.git', inhibit_warnings: true
  pod 'TrezorCrypto', inhibit_warnings: true

  target 'KeystoreBenchmark'
  target 'TrustKeystoreTests'
end
