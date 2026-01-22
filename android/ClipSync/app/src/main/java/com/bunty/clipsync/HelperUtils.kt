package com.bunty.clipsync

import java.util.regex.Pattern

object HelperUtils {
    // Regex for:
    // 1. 4-8 digits surrounded by word boundaries: \b\d{4,8}\b
    // 2. 3 digits -/space 3 digits: \b\d{3}[-\s]\d{3}\b
    // 3. Alphanumeric codes like G-123456: \b[A-Za-z]{0,3}-?\d{4,8}\b
    private val OTP_PATTERN = Pattern.compile("\\b(\\d{4,8})\\b|\\b(\\d{3}[-\\s]\\d{3})\\b|\\b([A-Za-z]{1,4}-?\\d{3,8})\\b")

    fun isOTP(text: String?): Boolean {
        if (text.isNullOrEmpty()) return false
        // Increase length check to allow "Your code is 123456"
        if (text.length > 100) return false
        return OTP_PATTERN.matcher(text).find()
    }
    
    fun extractOTP(text: String?): String? {
         if (text.isNullOrEmpty()) return null
         // Safety check for very long text
         if (text.length > 300) return null
         
         val matcher = OTP_PATTERN.matcher(text)
         if (matcher.find()) {
             return matcher.group(0)
         }
         return null
    }
}
