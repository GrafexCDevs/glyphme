package glyphme;

import haxe.macro.Expr.Field;
import haxe.macro.Context;

using Lambda;

class Macro {
	public static macro function modify():Array<Field> {
		final fields = Context.getBuildFields();
		fields.find((f:Field) -> f.name == 'getChar').access.remove(AInline);
		return fields;
	}
}