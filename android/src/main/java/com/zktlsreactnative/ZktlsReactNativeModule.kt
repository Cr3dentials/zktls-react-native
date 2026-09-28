package com.zktlsreactnative

import com.facebook.react.bridge.ReactApplicationContext

class ZktlsReactNativeModule(reactContext: ReactApplicationContext) :
  NativeZktlsReactNativeSpec(reactContext) {

  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  companion object {
    const val NAME = NativeZktlsReactNativeSpec.NAME
  }
}
