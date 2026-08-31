/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package mobile.input;

import flixel.system.macros.FlxMacroUtil;

/**
 * A high-level list of unique values for mobile input buttons.
 * Maps enum values and strings to unique integer codes
 * @author Karim Akra
 */
@:runtimeValue
enum abstract MobileInputID(Int) from Int to Int
{
	public static var fromStringMap(default, null):Map<String, MobileInputID> = FlxMacroUtil.buildMap("mobile.input.MobileInputID");
	public static var toStringMap(default, null):Map<MobileInputID, String> = FlxMacroUtil.buildMap("mobile.input.MobileInputID", true);
	// Nothing & Anything
	var ANY = -2;
	var NONE = -1;
	// Notes (4K)
	var NOTE_LEFT = 0;
	var NOTE_DOWN = 1;
	var NOTE_UP = 2;
	var NOTE_RIGHT = 3;
	// Touch Pad Buttons
	var A = 4;
	var B = 5;
	var C = 6;
	var D = 7;
	var E = 8;
	var F = 9;
	var G = 10;
	var H = 11;
	var I = 12;
	var J = 13;
	var K = 14;
	var L = 15;
	var M = 16;
	var N = 17;
	var O = 18;
	var P = 19;
	var Q = 20;
	var R = 21;
	var S = 22;
	var T = 23;
	var U = 24;
	var V = 25;
	var W = 26;
	var X = 27;
	var Y = 28;
	var Z = 29;
	// Touch Pad Directional Buttons
	var UP = 30;
	var UP2 = 31;
	var DOWN = 32;
	var DOWN2 = 33;
	var LEFT = 34;
	var LEFT2 = 35;
	var RIGHT = 36;
	var RIGHT2 = 37;
	// Hitbox Hints (4K)
	var HITBOX_UP = 38;
	var HITBOX_DOWN = 39;
	var HITBOX_LEFT = 40;
	var HITBOX_RIGHT = 41;
	// Extra Buttons
	var EXTRA_1 = 42;
	var EXTRA_2 = 43;

	// ============================================
	// 5K (44-48)
	// ============================================
	var NOTE_5K_1 = 44;
	var NOTE_5K_2 = 45;
	var NOTE_5K_3 = 46;
	var NOTE_5K_4 = 47;
	var NOTE_5K_5 = 48;

	// ============================================
	// 6K (49-54)
	// ============================================
	var NOTE_6K_1 = 49;
	var NOTE_6K_2 = 50;
	var NOTE_6K_3 = 51;
	var NOTE_6K_4 = 52;
	var NOTE_6K_5 = 53;
	var NOTE_6K_6 = 54;

	// ============================================
	// 7K (55-61)
	// ============================================
	var NOTE_7K_1 = 55;
	var NOTE_7K_2 = 56;
	var NOTE_7K_3 = 57;
	var NOTE_7K_4 = 58;
	var NOTE_7K_5 = 59;
	var NOTE_7K_6 = 60;
	var NOTE_7K_7 = 61;

	// ============================================
	// 8K (62-69)
	// ============================================
	var NOTE_8K_1 = 62;
	var NOTE_8K_2 = 63;
	var NOTE_8K_3 = 64;
	var NOTE_8K_4 = 65;
	var NOTE_8K_5 = 66;
	var NOTE_8K_6 = 67;
	var NOTE_8K_7 = 68;
	var NOTE_8K_8 = 69;

	// ============================================
	// 9K (70-78)
	// ============================================
	var NOTE_9K_1 = 70;
	var NOTE_9K_2 = 71;
	var NOTE_9K_3 = 72;
	var NOTE_9K_4 = 73;
	var NOTE_9K_5 = 74;
	var NOTE_9K_6 = 75;
	var NOTE_9K_7 = 76;
	var NOTE_9K_8 = 77;
	var NOTE_9K_9 = 78;

	// ============================================
	// 10K (79-88)
	// ============================================
	var NOTE_10K_1 = 79;
	var NOTE_10K_2 = 80;
	var NOTE_10K_3 = 81;
	var NOTE_10K_4 = 82;
	var NOTE_10K_5 = 83;
	var NOTE_10K_6 = 84;
	var NOTE_10K_7 = 85;
	var NOTE_10K_8 = 86;
	var NOTE_10K_9 = 87;
	var NOTE_10K_10 = 88;

	// ============================================
	// 11K (89-99)
	// ============================================
	var NOTE_11K_1 = 89;
	var NOTE_11K_2 = 90;
	var NOTE_11K_3 = 91;
	var NOTE_11K_4 = 92;
	var NOTE_11K_5 = 93;
	var NOTE_11K_6 = 94;
	var NOTE_11K_7 = 95;
	var NOTE_11K_8 = 96;
	var NOTE_11K_9 = 97;
	var NOTE_11K_10 = 98;
	var NOTE_11K_11 = 99;

	// ============================================
	// 12K (100-111)
	// ============================================
	var NOTE_12K_1 = 100;
	var NOTE_12K_2 = 101;
	var NOTE_12K_3 = 102;
	var NOTE_12K_4 = 103;
	var NOTE_12K_5 = 104;
	var NOTE_12K_6 = 105;
	var NOTE_12K_7 = 106;
	var NOTE_12K_8 = 107;
	var NOTE_12K_9 = 108;
	var NOTE_12K_10 = 109;
	var NOTE_12K_11 = 110;
	var NOTE_12K_12 = 111;

	// ============================================
	// 13K (112-124)
	// ============================================
	var NOTE_13K_1 = 112;
	var NOTE_13K_2 = 113;
	var NOTE_13K_3 = 114;
	var NOTE_13K_4 = 115;
	var NOTE_13K_5 = 116;
	var NOTE_13K_6 = 117;
	var NOTE_13K_7 = 118;
	var NOTE_13K_8 = 119;
	var NOTE_13K_9 = 120;
	var NOTE_13K_10 = 121;
	var NOTE_13K_11 = 122;
	var NOTE_13K_12 = 123;
	var NOTE_13K_13 = 124;

	// ============================================
	// 14K (125-138)
	// ============================================
	var NOTE_14K_1 = 125;
	var NOTE_14K_2 = 126;
	var NOTE_14K_3 = 127;
	var NOTE_14K_4 = 128;
	var NOTE_14K_5 = 129;
	var NOTE_14K_6 = 130;
	var NOTE_14K_7 = 131;
	var NOTE_14K_8 = 132;
	var NOTE_14K_9 = 133;
	var NOTE_14K_10 = 134;
	var NOTE_14K_11 = 135;
	var NOTE_14K_12 = 136;
	var NOTE_14K_13 = 137;
	var NOTE_14K_14 = 138;

	// ============================================
	// 15K (139-153)
	// ============================================
	var NOTE_15K_1 = 139;
	var NOTE_15K_2 = 140;
	var NOTE_15K_3 = 141;
	var NOTE_15K_4 = 142;
	var NOTE_15K_5 = 143;
	var NOTE_15K_6 = 144;
	var NOTE_15K_7 = 145;
	var NOTE_15K_8 = 146;
	var NOTE_15K_9 = 147;
	var NOTE_15K_10 = 148;
	var NOTE_15K_11 = 149;
	var NOTE_15K_12 = 150;
	var NOTE_15K_13 = 151;
	var NOTE_15K_14 = 152;
	var NOTE_15K_15 = 153;

	// ============================================
	// 16K (154-169)
	// ============================================
	var NOTE_16K_1 = 154;
	var NOTE_16K_2 = 155;
	var NOTE_16K_3 = 156;
	var NOTE_16K_4 = 157;
	var NOTE_16K_5 = 158;
	var NOTE_16K_6 = 159;
	var NOTE_16K_7 = 160;
	var NOTE_16K_8 = 161;
	var NOTE_16K_9 = 162;
	var NOTE_16K_10 = 163;
	var NOTE_16K_11 = 164;
	var NOTE_16K_12 = 165;
	var NOTE_16K_13 = 166;
	var NOTE_16K_14 = 167;
	var NOTE_16K_15 = 168;
	var NOTE_16K_16 = 169;

	@:from
	public static inline function fromString(s:String):MobileInputID
	{
		s = s.toUpperCase();
		return fromStringMap.exists(s) ? fromStringMap.get(s) : NONE;
	}

	@:to
	public inline function toString():String
	{
		return toStringMap.get(this);
	}
}