require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "ZktlsReactNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/Cr3dentials/zktls-react-native.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"
  s.swift_version = "5.0"

  # The native zkTLS SDK, from the releases repo's pod: the app's Podfile lists
  # https://github.com/Cr3dentials/zktls-sdk-releases.git as a source.
  s.dependency "ZktlsSDK", "~> 2.1", ">= 2.1.1"

  install_modules_dependencies(s)
end
