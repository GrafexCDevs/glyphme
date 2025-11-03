package glyphme;

import h3d.mat.Texture;
import hxd.Key;
import h2d.Font;
import h2d.Tile;
import hxd.Pixels;
import h2d.Font.FontChar;
import glyphme.GlyphMe;

/** Pass this to h2d.Text etc. It somewhat supports using consecutive fallback TrueTypeFontInfos 
 * to look up glyphs that it couldn't find in the previous TrueTypeFontInfo. */
class TrueTypeFont extends h2d.Font {
	public var infos:Array<TrueTypeFontInfo>;

	public var scaleMode:TrueTypeFontScaleMode = Ascent;

	// layout related, these will be calculated
	public var ascent:Float;
	public var descent:Float;
	public var lineGap:Float;
	public var lastGenerationParameters:TrueTypeFontGenerationParameters;

	private var pixels:Pixels;
	
	public function new(infos:Array<TrueTypeFontInfo>, sizeInPixels:Int, alphaCutOff:Float, smoothing:Float) {
		this.infos = infos;

		final first = infos[0];

		final scale = getScaleForPixelHeight(first, sizeInPixels);

		ascent = first.ascent * scale;
		descent = first.descent * scale;
		lineGap = first.lineGap * scale;

		super(null, sizeInPixels, h2d.Font.FontType.SignedDistanceField(Red, alphaCutOff, smoothing));

		this.lineHeight = sizeInPixels;
		this.baseLine = ascent;
		this.tile = @:privateAccess new Tile(null, 0, 0, 0, 0); // to avoid null access
	
		generateChar('?'.code);
	}

	private var __forceHasChar:Bool = false;

	override function hasChar(code:Int):Bool {
		if(code == Key.BACKSPACE) return false;
		if(Key.isDown(Key.CTRL)) return false;
		if (__forceHasChar)
			return true;
		return super.hasChar(code);
	}

	/** Fallbacks are used to look up glyphs from multiple fonts. When a glyph is not found
	 * we try the next font. If you have multiple fallbacks with slightly overlapping glyph support
	 * this might result in weird looking text, since we always stop at the first one found. 
	 * Also scale, line height ascent, descent are controlled by the first info. */
	public function addFallback(info:TrueTypeFontInfo) {
		infos.push(info);
	}

	/** Fallbacks are used to look up glyphs from multiple fonts. When a glyph is not found
	 * we try the next font. If you have multiple fallbacks with slightly overlapping glyph support
	 * this might result in weird looking text, since we always stop at the first one found. 
	 * Also scale, line height ascent, descent are controlled by the first info. */
	public function addFallbacks(infos:Array<TrueTypeFontInfo>) {
		for (info in infos)
			addFallback(info);
	}

	override function getChar(code:Int) {
		var c = glyphs.get(code);
		c ??= charset.resolveChar(code, glyphs);
		c ??= glyphs[code] = generateChar(code);
		c ??= charset.resolveChar(code, glyphs);
		c ??= (code == "\r".code || code == "\n".code ? nullChar : defaultChar);
		return c;
	}

	private function generateChar(code:Int):Null<FontChar> {
		var g:Null<TrueTypeFontGlyphInfo> = null;
		for (info in infos) {
			g = generateGlyph(code, info, {fontHeightInPixels: size});
			if (g == null) continue;

			// pixels ??= new Pixels(1, 1, null, RGBA);

			final width:Int = g.width, height:Int = g.height;
			glyphs[g.codePoint] = (width == 0 && height == 0)
				? new TrueTypeFontChar(this, g.fontInfo, g.index, Tile.fromColor(0xff000000, 0.0), g.advanceX)
				: {
					pixels ??= Pixels.alloc(width, height, RGBA);
					@:privateAccess {
						pixels.width = width;
						pixels.height = height;
						pixels.dataSize = width * height * 4;
						pixels.bytes = g.rgba.toBytes(pixels.dataSize);
					}

					final tile:Tile = Tile.fromPixels(pixels);
					tile.dx = g.offsetX;
					tile.dy = g.offsetY + size;

					new TrueTypeFontChar(this, g.fontInfo, g.index, tile, g.advanceX);
				}
			break;
		}
		return glyphs[code];
	}

	public override function clone():Font {
		final f = new TrueTypeFont(infos.copy(), size, 0, 0);
		f.baseLine = baseLine;
		f.lineHeight = lineHeight;
		f.tile = tile.clone();
		f.charset = charset;
		f.defaultChar = defaultChar.clone();
		f.type = type;
		for (g in glyphs.keys()) {
			var c = glyphs.get(g);
			var c2 = c.clone();
			if (c == defaultChar)
				f.defaultChar = c2;
			f.glyphs.set(g, c2);
		}

		f.infos = infos.copy();
		f.scaleMode = scaleMode;
		f.ascent = ascent;
		f.descent = descent;
		f.lineGap = lineGap;
		f.lastGenerationParameters = lastGenerationParameters;

		return f;
	}

	public override function resizeTo(size:Int) {
		final ratio = size / initSize;
		super.resizeTo(size);
		ascent = ascent * ratio;
		descent = descent * ratio;
		lineGap = lineGap * ratio;
	}

	function generateGlyph(code:Int, info:TrueTypeFontInfo, p:TrueTypeFontGenerationParameters):TrueTypeFontGlyphInfo {
		final scale = getScaleForPixelHeight(info, p.fontHeightInPixels);
		final g:TrueTypeFontGlyphInfo = cast GlyphMeNative.getGlyph(code, info.stbttFontInfo, scale, p.padding, p.onEdgeValue, p.pixelDistScale);
		if (g != null)
			g.fontInfo = info;

		return g;
	}

	public inline function getScaleForPixelHeight(info:TrueTypeFontInfo, height:Float) {
		return switch (scaleMode) {
			case Ascent:
				height / ( info.ascent - info.descent);
			case AscentAndDescent:
				height / (info.ascent + info.descent);
			case Custom(getScale):
				return getScale(info, height);
		}
	}

	@:noCompletion
	function drawPack(atlas:Pixels, x:Int, y:Int, w:Int, h:Int) {
		final color = new h3d.Vector4(1, 0, 0, 1).toColor();
		final thickness = 3;
		for (t in 0...thickness) {
			for (xl in 0...w)
				atlas.setPixel(x + xl, y + t, color);
			for (yl in 0...h)
				atlas.setPixel(x + t, y + yl, color);
		}
	}
}

class TrueTypeFontChar extends h2d.Font.FontChar {
	public var font:TrueTypeFont;
	public var fontInfo:TrueTypeFontInfo;
	public var index:Int;

	public function new(font, fontInfo, index, t, w) {
		this.font = font;
		this.fontInfo = fontInfo;
		this.index = index;

		super(t, w);
	}

	public override function getKerningOffset(prevChar:Int):Float {
		final previous:TrueTypeFontChar = cast @:privateAccess font.glyphs[prevChar];
		if (previous == null)
			return 0;

		final scale = font.getScaleForPixelHeight(fontInfo, font.size);
		final unscaled = GlyphMeNative.getKerning(fontInfo.stbttFontInfo, previous.index, index);

		return unscaled * scale + super.getKerningOffset(prevChar); // i don't know if the super call is relevant?
	}
}

typedef TrueTypeFontGlyphInfo = GlyphInfo & {fontInfo:TrueTypeFontInfo}

@:structInit
class TrueTypeFontGenerationParameters {
	/** character to use instead if the glyph cannot be resolved */
	public var unresolvedChar = "?";

	/** If true, will double atlasSize until all glyphs fit. (SLOW) **/
	public var autoFit = true;

	/** the width and height of the atlas on which glyphs will be generated. . */
	public var atlasSize = 1024;

	public var fontHeightInPixels:Int;

	/** extra pixels around the character which are filled with the distance to the character (not 0) */
	public var padding:Int = 2;

	/** value 0-255 to test the SDF against to reconstruct the character (i.e. the isocontour of the character)  */
	public var onEdgeValue:Int = 180;

	/** what value the SDF should increase by when moving one SDF "pixel" away from the edge (on the 0..255 scale)
	 * if positive, > onedge_value is inside; if negative, < onedge_value is inside */
	public var pixelDistScale:Float = 180;
}

/**
 * Choose how you want to define scale. I think heaps normally uses Ascent (how much the characters ascend above the baseline).
 * Or you could define it to include descent as well, stbtt does this by default. And I think it works better when using fallbacks as well.
 */
enum TrueTypeFontScaleMode {
	/**
	 * sizeInPixels / ascent;
	 */
	Ascent;

	/**
	 * sizeInPixels / (ascent + descent); ---(descent is negative)
	 */
	AscentAndDescent;

	/**
	 * Allows you to implement a custom scale function. For example AscentAndDescent is implemented as:
	 * return sizeInPixels / (ascent + descent); ---(descent is negative)
	 */
	Custom(getScale:(fontInfo:TrueTypeFontInfo, sizeInPixels:Float) -> Float);
}
