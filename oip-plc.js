var OipPlcBundle = (function(exports) {
	Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
	//#region src/plc/runtime.ts
	function isInt(t) {
		return t === "SINT" || t === "INT" || t === "DINT" || t === "BYTE" || t === "WORD" || t === "DWORD";
	}
	function isReal(t) {
		return t === "REAL" || t === "LREAL";
	}
	/** Coerce a number to its IEC integer type's bit width (two's-complement wrap). */
	function wrap(t, x) {
		switch (t) {
			case "SINT": return x << 24 >> 24;
			case "INT": return x << 16 >> 16;
			case "DINT": return x | 0;
			case "BYTE": return x & 255;
			case "WORD": return x & 65535;
			case "DWORD": return x >>> 0;
			default: return x;
		}
	}
	/** IEC integer division truncates toward zero (-7 / 2 = -3). Divide-by-zero -> 0. */
	function idiv(a, b) {
		return b === 0 ? 0 : Math.trunc(a / b);
	}
	/** IEC MOD: result takes the sign of the dividend. Mod-by-zero -> 0. */
	function imod(a, b) {
		return b === 0 ? 0 : a % b;
	}
	/** Width in bits of an integer/bit-string type (shifts and rotates work on this window). */
	function bitWidth(t) {
		return t === "SINT" || t === "BYTE" ? 8 : t === "INT" || t === "WORD" ? 16 : 32;
	}
	/** The unsigned value of `x`'s low `width(t)` bits — the bit string a shift/rotate sees. */
	function uval(t, x) {
		switch (t) {
			case "SINT":
			case "BYTE": return x & 255;
			case "INT":
			case "WORD": return x & 65535;
			default: return x >>> 0;
		}
	}
	/** Round to the nearest integer, ties to even — the IEC rule for REAL->integer conversion. */
	function roundEven(x) {
		const f = Math.floor(x);
		const d = x - f;
		if (d < .5) return f;
		if (d > .5) return f + 1;
		return f % 2 === 0 ? f : f + 1;
	}
	/** SHL — logical left shift of `x` by `n` bits within its type's width (zero-filled). */
	function shl(t, x, n) {
		n = Math.trunc(n);
		if (n <= 0) return wrap(t, x);
		const w = bitWidth(t);
		if (n >= w) return wrap(t, 0);
		return wrap(t, uval(t, x) << n);
	}
	/** SHR — logical right shift of `x` by `n` bits within its type's width (zero-filled). */
	function shr(t, x, n) {
		n = Math.trunc(n);
		if (n <= 0) return wrap(t, x);
		const w = bitWidth(t);
		if (n >= w) return wrap(t, 0);
		return wrap(t, uval(t, x) >>> n);
	}
	/** ROL — rotate `x` left by `n` bits within its type's width (bits wrap around). */
	function rol(t, x, n) {
		const w = bitWidth(t);
		n = (Math.trunc(n) % w + w) % w;
		if (n === 0) return wrap(t, x);
		const u = uval(t, x);
		return wrap(t, w === 32 ? (u << n | u >>> w - n) >>> 0 : (u << n | u >>> w - n) & (1 << w) - 1);
	}
	/** ROR — rotate `x` right by `n` bits within its type's width (bits wrap around). */
	function ror(t, x, n) {
		const w = bitWidth(t);
		n = (Math.trunc(n) % w + w) % w;
		return n === 0 ? wrap(t, x) : rol(t, x, w - n);
	}
	/** IEC type conversion `<src>_TO_<dst>`: REAL->int rounds (ties to even); int->int reinterprets
	*  the low bits (two's-complement wrap); anything ->BOOL is `<> 0`. */
	function conv(src, dst, v) {
		const n = typeof v === "boolean" ? v ? 1 : 0 : v;
		if (dst === "BOOL") return n !== 0;
		if (isReal(dst)) return n;
		return wrap(dst, isReal(src) ? roundEven(n) : n);
	}
	function num(v) {
		return typeof v === "number" ? v : v ? 1 : 0;
	}
	function bool$1(v) {
		return typeof v === "boolean" ? v : v !== 0;
	}
	/** TON — on-delay timer. Q goes true once IN has been true for PT seconds. */
	var Ton = class {
		Q = false;
		ET = 0;
		call(a, dt) {
			const pt = num(a.PT ?? 0);
			if (bool$1(a.IN ?? false)) {
				this.ET = Math.min(pt, this.ET + dt);
				this.Q = this.ET >= pt;
			} else {
				this.ET = 0;
				this.Q = false;
			}
		}
	};
	/** TOF — off-delay timer. Q goes true with IN, stays true for PT after IN falls. */
	var Tof = class {
		Q = false;
		ET = 0;
		call(a, dt) {
			const pt = num(a.PT ?? 0);
			if (bool$1(a.IN ?? false)) {
				this.Q = true;
				this.ET = 0;
			} else {
				this.ET = Math.min(pt, this.ET + dt);
				this.Q = this.ET < pt;
			}
		}
	};
	/** TP — pulse timer. A rising edge on IN starts a fixed pulse: Q is true for PT seconds
	*  (ET ramps 0->PT), and IN changes during the pulse are ignored until it completes. */
	var Tp = class {
		Q = false;
		ET = 0;
		#prev = false;
		#timing = false;
		call(a, dt) {
			const pt = num(a.PT ?? 0);
			const inn = bool$1(a.IN ?? false);
			if (!this.#timing && inn && !this.#prev) {
				this.#timing = true;
				this.ET = 0;
			}
			if (this.#timing) {
				this.ET = Math.min(pt, this.ET + dt);
				this.Q = true;
				if (this.ET >= pt) this.#timing = false;
			} else {
				this.Q = false;
				if (!inn) this.ET = 0;
			}
			this.#prev = inn;
		}
	};
	/** R_TRIG — rising-edge one-shot. Q is true for the single scan after CLK 0->1. */
	var RTrig = class {
		Q = false;
		#prev = false;
		call(a) {
			const clk = bool$1(a.CLK ?? false);
			this.Q = clk && !this.#prev;
			this.#prev = clk;
		}
	};
	/** F_TRIG — falling-edge one-shot. */
	var FTrig = class {
		Q = false;
		#prev = true;
		call(a) {
			const clk = bool$1(a.CLK ?? false);
			this.Q = !clk && this.#prev;
			this.#prev = clk;
		}
	};
	/** CTU — count up on rising CU; Q when CV >= PV; RESET zeroes CV. */
	var Ctu = class {
		CV = 0;
		Q = false;
		#prev = false;
		call(a) {
			const cu = bool$1(a.CU ?? false);
			if (bool$1(a.RESET ?? false)) this.CV = 0;
			else if (cu && !this.#prev) this.CV++;
			this.#prev = cu;
			this.Q = this.CV >= num(a.PV ?? 0);
		}
	};
	/** CTD — load PV on LD, count down on rising CD (not below 0); Q when CV <= 0. */
	var Ctd = class {
		CV = 0;
		Q = false;
		#prev = false;
		call(a) {
			const cd = bool$1(a.CD ?? false);
			if (bool$1(a.LD ?? false)) this.CV = num(a.PV ?? 0);
			else if (cd && !this.#prev && this.CV > 0) this.CV--;
			this.#prev = cd;
			this.Q = this.CV <= 0;
		}
	};
	/** CTUD — up/down counter. Rising CU counts up, rising CD counts down (clamped to the INT
	*  range); RESET zeroes CV, LD loads PV. QU = CV >= PV, QD = CV <= 0. */
	var Ctud = class {
		CV = 0;
		QU = false;
		QD = false;
		#pcu = false;
		#pcd = false;
		call(a) {
			const cu = bool$1(a.CU ?? false);
			const cd = bool$1(a.CD ?? false);
			const pv = num(a.PV ?? 0);
			if (bool$1(a.RESET ?? false)) this.CV = 0;
			else if (bool$1(a.LD ?? false)) this.CV = pv;
			else {
				if (cu && !this.#pcu && this.CV < 32767) this.CV++;
				if (cd && !this.#pcd && this.CV > -32768) this.CV--;
			}
			this.#pcu = cu;
			this.#pcd = cd;
			this.QU = this.CV >= pv;
			this.QD = this.CV <= 0;
		}
	};
	function makeFb(type) {
		switch (type) {
			case "TON": return new Ton();
			case "TOF": return new Tof();
			case "TP": return new Tp();
			case "R_TRIG": return new RTrig();
			case "F_TRIG": return new FTrig();
			case "CTU": return new Ctu();
			case "CTD": return new Ctd();
			case "CTUD": return new Ctud();
		}
	}
	/** Type of a function-block output member, or null if the FB has no such output. */
	function fbMemberType(fb, member) {
		if (member === "Q" && fb !== "CTUD") return "BOOL";
		if (member === "ET" && (fb === "TON" || fb === "TOF" || fb === "TP")) return "REAL";
		if (member === "CV" && (fb === "CTU" || fb === "CTD" || fb === "CTUD")) return "INT";
		if ((member === "QU" || member === "QD") && fb === "CTUD") return "BOOL";
		return null;
	}
	//#endregion
	//#region src/plc/types.ts
	var SCALAR_TYPES = [
		"BOOL",
		"SINT",
		"INT",
		"DINT",
		"BYTE",
		"WORD",
		"DWORD",
		"REAL",
		"LREAL"
	];
	var FB_TYPES = [
		"TON",
		"TOF",
		"TP",
		"R_TRIG",
		"F_TRIG",
		"CTU",
		"CTD",
		"CTUD"
	];
	/** True when a declared type is a user-defined function-block instance (vs a builtin). */
	function isUserFb(t) {
		return typeof t === "object" && "fb" in t;
	}
	/** True when a declared type is an array. */
	function isArray(t) {
		return typeof t === "object" && "array" in t;
	}
	/** True when a declared type is a struct instance. */
	function isStruct(t) {
		return typeof t === "object" && "struct" in t;
	}
	/** A compile/parse error carrying a source position so editors can place a marker. */
	var StError = class extends Error {
		pos;
		length;
		constructor(message, pos, length = 1) {
			super(message);
			this.pos = pos;
			this.length = length;
			this.name = "StError";
		}
	};
	//#endregion
	//#region src/plc/builtins.ts
	/** The fixed-name builtins (the conversion family `X_TO_Y` is recognised separately). */
	var FN_NAMES = new Set([
		"ABS",
		"MIN",
		"MAX",
		"LIMIT",
		"SEL",
		"MUX",
		"SQRT",
		"LN",
		"LOG",
		"EXP",
		"EXPT",
		"SIN",
		"COS",
		"TAN",
		"ASIN",
		"ACOS",
		"ATAN",
		"TRUNC",
		"SHL",
		"SHR",
		"ROL",
		"ROR"
	]);
	[...FN_NAMES].sort();
	/** Parse a `<src>_TO_<dst>` conversion name into its scalar endpoints, or null if not one. */
	function parseConv(name) {
		const m = name.match(/^([A-Z]+)_TO_([A-Z]+)$/);
		if (!m) return null;
		const src = m[1];
		const dst = m[2];
		const scalars = SCALAR_TYPES;
		return scalars.includes(src) && scalars.includes(dst) ? {
			src,
			dst
		} : null;
	}
	/** True when `name` is a standard function (so the checker resolves it as a builtin, not a user FUNCTION). */
	function isBuiltinFunc(name) {
		return FN_NAMES.has(name) || parseConv(name) !== null;
	}
	var NUM_RANK = {
		SINT: 1,
		BYTE: 1,
		INT: 2,
		WORD: 2,
		DINT: 3,
		DWORD: 3,
		REAL: 4,
		LREAL: 5
	};
	function widenNum(a, b) {
		return (NUM_RANK[a] ?? 0) >= (NUM_RANK[b] ?? 0) ? a : b;
	}
	function arity(name, got, min, max, pos) {
		if (got >= min && got <= max) return;
		throw new StError(`'${name}' expects ${min === max ? `${min}` : max === Infinity ? `at least ${min}` : `${min}..${max}`} argument(s), got ${got}`, pos, name.length);
	}
	function needNum(name, t, pos) {
		if (t === "BOOL") throw new StError(`'${name}' needs a numeric argument`, pos, name.length);
		return t;
	}
	function needInt(name, t, pos) {
		if (!isInt(t)) throw new StError(`'${name}' needs an integer argument`, pos, name.length);
		return t;
	}
	/** SEL/MUX result: all-BOOL stays BOOL, all-numeric widens; mixing the two is an error. */
	function combineSelectands(name, types, pos) {
		if (types.every((t) => t === "BOOL")) return "BOOL";
		if (types.some((t) => t === "BOOL")) throw new StError(`'${name}' branches must be the same kind`, pos, name.length);
		return types.reduce(widenNum);
	}
	/** Validate a builtin call's arguments and return its result type. Assumes `isBuiltinFunc(name)`. */
	function builtinResultType(name, argTypes, pos) {
		const cv = parseConv(name);
		if (cv) {
			arity(name, argTypes.length, 1, 1, pos);
			return cv.dst;
		}
		const n = argTypes.length;
		switch (name) {
			case "ABS":
				arity(name, n, 1, 1, pos);
				return needNum(name, argTypes[0], pos);
			case "MIN":
			case "MAX":
			case "LIMIT":
				arity(name, n, name === "LIMIT" ? 3 : 2, name === "LIMIT" ? 3 : Infinity, pos);
				argTypes.forEach((t) => needNum(name, t, pos));
				return argTypes.reduce(widenNum);
			case "SEL":
				arity(name, n, 3, 3, pos);
				if (argTypes[0] !== "BOOL") throw new StError(`'SEL' selector (1st arg) must be BOOL`, pos, name.length);
				return combineSelectands(name, [argTypes[1], argTypes[2]], pos);
			case "MUX":
				arity(name, n, 2, Infinity, pos);
				needInt(name, argTypes[0], pos);
				return combineSelectands(name, argTypes.slice(1), pos);
			case "SQRT":
			case "LN":
			case "LOG":
			case "EXP":
			case "SIN":
			case "COS":
			case "TAN":
			case "ASIN":
			case "ACOS":
			case "ATAN":
				arity(name, n, 1, 1, pos);
				needNum(name, argTypes[0], pos);
				return "REAL";
			case "EXPT":
				arity(name, n, 2, 2, pos);
				argTypes.forEach((t) => needNum(name, t, pos));
				return "REAL";
			case "TRUNC":
				arity(name, n, 1, 1, pos);
				needNum(name, argTypes[0], pos);
				return "DINT";
			case "SHL":
			case "SHR":
			case "ROL":
			case "ROR":
				arity(name, n, 2, 2, pos);
				needInt(name, argTypes[0], pos);
				needInt(name, argTypes[1], pos);
				return argTypes[0];
		}
		throw new StError(`unknown function '${name}'`, pos, name.length);
	}
	/** Coerce a computed number to an integer result type (no-op for REAL results). */
	function coerceNum(rt, x) {
		return isInt(rt) ? wrap(rt, x) : x;
	}
	/** Evaluate a builtin call given its result type and already-evaluated scalar args. */
	function evalBuiltin(name, rt, args) {
		const cv = parseConv(name);
		if (cv) return conv(cv.src, cv.dst, args[0]);
		switch (name) {
			case "ABS": return coerceNum(rt, Math.abs(num(args[0])));
			case "MIN": return coerceNum(rt, Math.min(...args.map(num)));
			case "MAX": return coerceNum(rt, Math.max(...args.map(num)));
			case "LIMIT": return coerceNum(rt, Math.min(Math.max(num(args[1]), num(args[0])), num(args[2])));
			case "SEL": return bool(args[0]) ? args[2] : args[1];
			case "MUX": return args[1 + num(args[0])] ?? 0;
			case "SQRT": return Math.sqrt(num(args[0]));
			case "LN": return Math.log(num(args[0]));
			case "LOG": return Math.log10(num(args[0]));
			case "EXP": return Math.exp(num(args[0]));
			case "SIN": return Math.sin(num(args[0]));
			case "COS": return Math.cos(num(args[0]));
			case "TAN": return Math.tan(num(args[0]));
			case "ASIN": return Math.asin(num(args[0]));
			case "ACOS": return Math.acos(num(args[0]));
			case "ATAN": return Math.atan(num(args[0]));
			case "EXPT": return Math.pow(num(args[0]), num(args[1]));
			case "TRUNC": return wrap("DINT", Math.trunc(num(args[0])));
			case "SHL": return shl(rt, num(args[0]), num(args[1]));
			case "SHR": return shr(rt, num(args[0]), num(args[1]));
			case "ROL": return rol(rt, num(args[0]), num(args[1]));
			case "ROR": return ror(rt, num(args[0]), num(args[1]));
		}
		throw new Error(`unknown builtin '${name}'`);
	}
	/** `bool`, inlined here to avoid importing the whole runtime surface for one coercion. */
	function bool(v) {
		return typeof v === "boolean" ? v : v !== 0;
	}
	//#endregion
	//#region src/plc/lexer.ts
	var KEYWORDS = new Set([
		...SCALAR_TYPES,
		...FB_TYPES,
		"VAR",
		"VAR_INPUT",
		"VAR_OUTPUT",
		"VAR_TEMP",
		"END_VAR",
		"IF",
		"THEN",
		"ELSIF",
		"ELSE",
		"END_IF",
		"CASE",
		"OF",
		"END_CASE",
		"FOR",
		"TO",
		"BY",
		"DO",
		"END_FOR",
		"WHILE",
		"END_WHILE",
		"REPEAT",
		"UNTIL",
		"END_REPEAT",
		"EXIT",
		"FUNCTION_BLOCK",
		"END_FUNCTION_BLOCK",
		"FUNCTION",
		"END_FUNCTION",
		"ARRAY",
		"TYPE",
		"END_TYPE",
		"STRUCT",
		"END_STRUCT",
		"AND",
		"OR",
		"XOR",
		"NOT",
		"MOD",
		"TRUE",
		"FALSE"
	]);
	var TWO_CHAR = new Set([
		":=",
		"<>",
		"<=",
		">=",
		".."
	]);
	var ONE_CHAR = new Set([
		"+",
		"-",
		"*",
		"/",
		"(",
		")",
		"[",
		"]",
		"<",
		">",
		"=",
		",",
		";",
		":",
		"."
	]);
	function isIdentStart(c) {
		return /[A-Za-z_]/.test(c);
	}
	function isIdentPart(c) {
		return /[A-Za-z0-9_]/.test(c);
	}
	/** Parse a duration literal body (after `T#`) into seconds, e.g. `1m30s` -> 90. */
	function parseDuration(body) {
		let total = 0;
		const re = /(\d+(?:\.\d+)?)(ms|h|m|s)/gi;
		let m;
		while ((m = re.exec(body)) !== null) {
			const v = Number(m[1] ?? 0);
			switch ((m[2] ?? "").toLowerCase()) {
				case "ms":
					total += v / 1e3;
					break;
				case "s":
					total += v;
					break;
				case "m":
					total += v * 60;
					break;
				case "h":
					total += v * 3600;
					break;
			}
		}
		return total;
	}
	function lex(src) {
		const toks = [];
		let i = 0;
		let line = 1;
		let col = 1;
		const here = () => ({
			line,
			col,
			offset: i
		});
		const advance = (n = 1) => {
			for (let k = 0; k < n; k++) {
				if (src[i] === "\n") {
					line++;
					col = 1;
				} else col++;
				i++;
			}
		};
		while (i < src.length) {
			const c = src[i];
			if (c === " " || c === "	" || c === "\r" || c === "\n") {
				advance();
				continue;
			}
			if (c === "/" && src[i + 1] === "/") {
				while (i < src.length && src[i] !== "\n") advance();
				continue;
			}
			if (c === "(" && src[i + 1] === "*") {
				const start = here();
				advance(2);
				while (i < src.length && !(src[i] === "*" && src[i + 1] === ")")) advance();
				if (i >= src.length) throw new StError("unterminated comment", start);
				advance(2);
				continue;
			}
			if ((c === "T" || c === "t") && src[i + 1] === "#") {
				const pos = here();
				advance(2);
				let body = "";
				while (i < src.length && /[0-9a-zA-Z._]/.test(src[i])) {
					body += src[i];
					advance();
				}
				toks.push({
					kind: "num",
					value: body,
					num: parseDuration(body),
					real: true,
					pos
				});
				continue;
			}
			if (/[0-9]/.test(c)) {
				const pos = here();
				let raw = "";
				let real = false;
				while (i < src.length) {
					const ch = src[i];
					if (/[0-9_]/.test(ch)) {
						raw += ch;
						advance();
					} else if (ch === "." && /[0-9]/.test(src[i + 1] ?? "")) {
						real = true;
						raw += ch;
						advance();
					} else break;
				}
				toks.push({
					kind: "num",
					value: raw,
					num: Number(raw.replace(/_/g, "")),
					real,
					pos
				});
				continue;
			}
			if (isIdentStart(c)) {
				const pos = here();
				let id = "";
				while (i < src.length && isIdentPart(src[i])) {
					id += src[i];
					advance();
				}
				const up = id.toUpperCase();
				toks.push({
					kind: KEYWORDS.has(up) ? "kw" : "ident",
					value: KEYWORDS.has(up) ? up : id,
					num: 0,
					real: false,
					pos
				});
				continue;
			}
			const two = src.substr(i, 2);
			if (TWO_CHAR.has(two)) {
				const pos = here();
				advance(2);
				toks.push({
					kind: "op",
					value: two,
					num: 0,
					real: false,
					pos
				});
				continue;
			}
			if (ONE_CHAR.has(c)) {
				const pos = here();
				advance();
				toks.push({
					kind: "op",
					value: c,
					num: 0,
					real: false,
					pos
				});
				continue;
			}
			throw new StError(`unexpected character '${c}'`, here());
		}
		toks.push({
			kind: "eof",
			value: "",
			num: 0,
			real: false,
			pos: here()
		});
		return toks;
	}
	//#endregion
	//#region src/plc/parser.ts
	var VAR_SECTIONS = new Set([
		"VAR",
		"VAR_INPUT",
		"VAR_OUTPUT",
		"VAR_TEMP"
	]);
	var TYPE_KW = new Set([...SCALAR_TYPES, ...FB_TYPES]);
	var COMPARE = new Set([
		"=",
		"<>",
		"<",
		">",
		"<=",
		">="
	]);
	var Parser = class {
		toks;
		p = 0;
		constructor(toks) {
			this.toks = toks;
		}
		peek(k = 0) {
			return this.toks[Math.min(this.p + k, this.toks.length - 1)];
		}
		next() {
			return this.toks[this.p++];
		}
		isOp(v) {
			const t = this.peek();
			return t.kind === "op" && t.value === v;
		}
		isKw(v) {
			const t = this.peek();
			return t.kind === "kw" && t.value === v;
		}
		eatOp(v) {
			if (!this.isOp(v)) throw new StError(`expected '${v}'`, this.peek().pos);
			return this.next();
		}
		eatKw(v) {
			if (!this.isKw(v)) throw new StError(`expected ${v}`, this.peek().pos);
			return this.next();
		}
		parse() {
			const typeDefs = [];
			const fbDefs = [];
			const funcDefs = [];
			for (;;) if (this.isKw("TYPE")) typeDefs.push(...this.typeBlock());
			else if (this.isKw("FUNCTION_BLOCK")) fbDefs.push(this.fbDef());
			else if (this.isKw("FUNCTION")) funcDefs.push(this.funcDef());
			else break;
			const decls = this.varSections();
			const body = this.stmtList();
			if (this.peek().kind !== "eof") throw new StError(`unexpected '${this.peek().value}'`, this.peek().pos);
			return {
				typeDefs,
				fbDefs,
				funcDefs,
				decls,
				body
			};
		}
		/** a TYPE ... END_TYPE block holding one or more struct definitions */
		typeBlock() {
			this.eatKw("TYPE");
			const defs = [];
			while (!this.isKw("END_TYPE")) {
				if (this.peek().kind === "eof") throw new StError("expected END_TYPE", this.peek().pos);
				defs.push(this.structDef());
			}
			this.eatKw("END_TYPE");
			if (this.isOp(";")) this.next();
			return defs;
		}
		structDef() {
			const nameTok = this.peek();
			if (nameTok.kind !== "ident") throw new StError("expected a type name", nameTok.pos);
			this.next();
			this.eatOp(":");
			this.eatKw("STRUCT");
			const fields = [];
			while (!this.isKw("END_STRUCT")) {
				if (this.peek().kind === "eof") throw new StError("expected END_STRUCT", this.peek().pos);
				const fn = this.peek();
				if (fn.kind !== "ident") throw new StError("expected a field name", fn.pos);
				this.next();
				this.eatOp(":");
				const type = this.dataType();
				this.eatOp(";");
				fields.push({
					name: fn.value,
					type,
					pos: fn.pos
				});
			}
			this.eatKw("END_STRUCT");
			if (this.isOp(";")) this.next();
			return {
				name: nameTok.value,
				fields,
				pos: nameTok.pos
			};
		}
		/** zero or more VAR / VAR_INPUT / VAR_OUTPUT / VAR_TEMP sections */
		varSections() {
			const decls = [];
			while (this.peek().kind === "kw" && VAR_SECTIONS.has(this.peek().value)) {
				const section = this.next().value;
				while (!this.isKw("END_VAR")) {
					if (this.peek().kind === "eof") throw new StError("expected END_VAR", this.peek().pos);
					decls.push(this.decl(section));
				}
				this.eatKw("END_VAR");
			}
			return decls;
		}
		fbDef() {
			const pos = this.eatKw("FUNCTION_BLOCK").pos;
			const nameTok = this.peek();
			if (nameTok.kind !== "ident") throw new StError("expected a function block name", nameTok.pos);
			this.next();
			const decls = this.varSections();
			const body = this.stmtList(() => this.isKw("END_FUNCTION_BLOCK"));
			this.eatKw("END_FUNCTION_BLOCK");
			if (this.isOp(";")) this.next();
			return {
				name: nameTok.value,
				decls,
				body,
				pos
			};
		}
		funcDef() {
			const pos = this.eatKw("FUNCTION").pos;
			const nameTok = this.peek();
			if (nameTok.kind !== "ident") throw new StError("expected a function name", nameTok.pos);
			this.next();
			this.eatOp(":");
			const retTok = this.peek();
			if (retTok.kind !== "kw" || !SCALAR_TYPES.includes(retTok.value)) throw new StError("a function must return a scalar type", retTok.pos);
			this.next();
			const decls = this.varSections();
			const body = this.stmtList(() => this.isKw("END_FUNCTION"));
			this.eatKw("END_FUNCTION");
			if (this.isOp(";")) this.next();
			return {
				name: nameTok.value,
				ret: retTok.value,
				decls,
				body,
				pos
			};
		}
		decl(section) {
			const nameTok = this.peek();
			if (nameTok.kind !== "ident") throw new StError("expected variable name", nameTok.pos);
			this.next();
			this.eatOp(":");
			const typeTok = this.peek();
			let type;
			if (typeTok.kind === "kw" && typeTok.value === "ARRAY") type = this.arrayType();
			else if (typeTok.kind === "kw" && TYPE_KW.has(typeTok.value)) {
				this.next();
				type = typeTok.value;
			} else if (typeTok.kind === "ident") {
				this.next();
				type = { fb: typeTok.value };
			} else throw new StError("expected a type", typeTok.pos);
			let init = null;
			if (this.isOp(":=")) {
				if (isArray(type)) throw new StError("array initializers are not supported yet", this.peek().pos);
				this.next();
				init = this.expr();
			}
			this.eatOp(";");
			return {
				name: nameTok.value,
				type,
				init,
				section,
				pos: nameTok.pos
			};
		}
		arrayType() {
			this.eatKw("ARRAY");
			this.eatOp("[");
			const dims = [];
			for (;;) {
				const lo = this.intLiteral();
				this.eatOp("..");
				const hiPos = this.peek().pos;
				const hi = this.intLiteral();
				if (hi < lo) throw new StError("array bounds must be ascending (lo..hi)", hiPos);
				dims.push({
					lo,
					hi
				});
				if (this.isOp(",")) {
					this.next();
					continue;
				}
				break;
			}
			this.eatOp("]");
			this.eatKw("OF");
			return {
				array: true,
				dims,
				elem: this.elemType()
			};
		}
		/** an array element type: scalar or struct (use multiple dims for N-D, not nested arrays) */
		elemType() {
			const t = this.peek();
			if (t.kind === "kw" && SCALAR_TYPES.includes(t.value)) {
				this.next();
				return t.value;
			}
			if (t.kind === "ident") {
				this.next();
				return { struct: t.value };
			}
			throw new StError("array element type must be a scalar or struct", t.pos);
		}
		/** a struct-field type: scalar, array, or nested struct */
		dataType() {
			const t = this.peek();
			if (t.kind === "kw" && t.value === "ARRAY") return this.arrayType();
			if (t.kind === "kw" && SCALAR_TYPES.includes(t.value)) {
				this.next();
				return t.value;
			}
			if (t.kind === "ident") {
				this.next();
				return { struct: t.value };
			}
			throw new StError("expected a type", t.pos);
		}
		intLiteral() {
			let neg = false;
			if (this.isOp("-")) {
				this.next();
				neg = true;
			}
			const t = this.peek();
			if (t.kind !== "num" || t.real) throw new StError("expected an integer", t.pos);
			this.next();
			return neg ? -t.num : t.num;
		}
		/** statements until `atEnd` (a block terminator) or EOF; `;` separators are optional */
		stmtList(atEnd = () => false) {
			const out = [];
			for (;;) {
				if (this.peek().kind === "eof") break;
				if (atEnd()) break;
				if (this.isOp(";")) {
					this.next();
					continue;
				}
				out.push(this.stmt());
			}
			return out;
		}
		stmt() {
			if (this.isKw("IF")) return this.ifStmt();
			if (this.isKw("CASE")) return this.caseStmt();
			if (this.isKw("FOR")) return this.forStmt();
			if (this.isKw("WHILE")) return this.whileStmt();
			if (this.isKw("REPEAT")) return this.repeatStmt();
			if (this.isKw("EXIT")) return this.exitStmt();
			const head = this.peek();
			if (head.kind === "ident") {
				if (this.peek(1).kind === "op" && this.peek(1).value === "(") {
					this.next();
					this.next();
					const args = [];
					while (!this.isOp(")")) {
						const argTok = this.peek();
						if (argTok.kind !== "ident") throw new StError("expected parameter name", argTok.pos);
						this.next();
						this.eatOp(":=");
						const value = this.expr();
						args.push({
							name: argTok.value,
							value,
							pos: argTok.pos
						});
						if (this.isOp(",")) this.next();
						else break;
					}
					this.eatOp(")");
					this.eatOp(";");
					return {
						node: "fbcall",
						inst: head.value,
						args,
						pos: head.pos
					};
				}
				this.next();
				const target = this.accessChain({
					node: "var",
					name: head.value,
					pos: head.pos
				});
				this.eatOp(":=");
				const value = this.expr();
				this.eatOp(";");
				return {
					node: "assign",
					target,
					value,
					pos: head.pos
				};
			}
			throw new StError(`unsupported statement near '${head.value || head.kind}'`, head.pos);
		}
		/** consume a chain of `.field` and `[i, j, ...]` accessors onto a base place */
		accessChain(base) {
			let e = base;
			for (;;) if (this.isOp(".")) {
				this.next();
				const m = this.peek();
				if (m.kind !== "ident" && m.kind !== "kw") throw new StError("expected a field name", m.pos);
				this.next();
				e = {
					node: "member",
					obj: e,
					field: m.value,
					pos: base.pos
				};
			} else if (this.isOp("[")) {
				this.next();
				const indices = [this.expr()];
				while (this.isOp(",")) {
					this.next();
					indices.push(this.expr());
				}
				this.eatOp("]");
				e = {
					node: "index",
					obj: e,
					indices,
					pos: base.pos
				};
			} else return e;
		}
		ifStmt() {
			const pos = this.eatKw("IF").pos;
			const atEnd = () => this.isKw("ELSIF") || this.isKw("ELSE") || this.isKw("END_IF");
			const branches = [];
			let cond = this.expr();
			this.eatKw("THEN");
			branches.push({
				cond,
				body: this.stmtList(atEnd)
			});
			while (this.isKw("ELSIF")) {
				this.next();
				cond = this.expr();
				this.eatKw("THEN");
				branches.push({
					cond,
					body: this.stmtList(atEnd)
				});
			}
			let elseBody = null;
			if (this.isKw("ELSE")) {
				this.next();
				elseBody = this.stmtList(atEnd);
			}
			this.eatKw("END_IF");
			if (this.isOp(";")) this.next();
			return {
				node: "if",
				branches,
				elseBody,
				pos
			};
		}
		caseStmt() {
			const pos = this.eatKw("CASE").pos;
			const selector = this.expr();
			this.eatKw("OF");
			const cases = [];
			while (!this.isKw("ELSE") && !this.isKw("END_CASE")) {
				if (this.peek().kind === "eof") throw new StError("expected END_CASE", this.peek().pos);
				const labels = this.caseLabels();
				this.eatOp(":");
				cases.push({
					labels,
					body: this.stmtList(() => this.isCaseClauseEnd())
				});
			}
			let elseBody = null;
			if (this.isKw("ELSE")) {
				this.next();
				elseBody = this.stmtList(() => this.isKw("END_CASE"));
			}
			this.eatKw("END_CASE");
			if (this.isOp(";")) this.next();
			return {
				node: "case",
				selector,
				cases,
				elseBody,
				pos
			};
		}
		/** a clause body ends at the next label (an int literal, possibly signed) or ELSE/END_CASE */
		isCaseClauseEnd() {
			const t = this.peek();
			if (t.kind === "num") return true;
			if (t.kind === "op" && t.value === "-") return true;
			return this.isKw("ELSE") || this.isKw("END_CASE");
		}
		caseLabels() {
			const labels = [];
			for (;;) {
				const lo = this.caseInt();
				if (this.isOp("..")) {
					this.next();
					const hiPos = this.peek().pos;
					const hi = this.caseInt();
					if (hi < lo) throw new StError("CASE range must be ascending (lo..hi)", hiPos);
					labels.push({
						kind: "range",
						lo,
						hi
					});
				} else labels.push({
					kind: "single",
					value: lo
				});
				if (this.isOp(",")) {
					this.next();
					continue;
				}
				break;
			}
			return labels;
		}
		caseInt() {
			let neg = false;
			if (this.isOp("-")) {
				this.next();
				neg = true;
			}
			const t = this.peek();
			if (t.kind !== "num" || t.real) throw new StError("expected an integer CASE label", t.pos);
			this.next();
			return neg ? -t.num : t.num;
		}
		forStmt() {
			const pos = this.eatKw("FOR").pos;
			const varTok = this.peek();
			if (varTok.kind !== "ident") throw new StError("expected a loop variable", varTok.pos);
			this.next();
			this.eatOp(":=");
			const from = this.expr();
			this.eatKw("TO");
			const to = this.expr();
			let by = null;
			if (this.isKw("BY")) {
				this.next();
				by = this.expr();
			}
			this.eatKw("DO");
			const body = this.stmtList(() => this.isKw("END_FOR"));
			this.eatKw("END_FOR");
			if (this.isOp(";")) this.next();
			return {
				node: "for",
				varName: varTok.value,
				from,
				to,
				by,
				body,
				pos
			};
		}
		whileStmt() {
			const pos = this.eatKw("WHILE").pos;
			const cond = this.expr();
			this.eatKw("DO");
			const body = this.stmtList(() => this.isKw("END_WHILE"));
			this.eatKw("END_WHILE");
			if (this.isOp(";")) this.next();
			return {
				node: "while",
				cond,
				body,
				pos
			};
		}
		repeatStmt() {
			const pos = this.eatKw("REPEAT").pos;
			const body = this.stmtList(() => this.isKw("UNTIL"));
			this.eatKw("UNTIL");
			const cond = this.expr();
			this.eatKw("END_REPEAT");
			if (this.isOp(";")) this.next();
			return {
				node: "repeat",
				body,
				cond,
				pos
			};
		}
		exitStmt() {
			const pos = this.eatKw("EXIT").pos;
			if (this.isOp(";")) this.next();
			return {
				node: "exit",
				pos
			};
		}
		expr() {
			return this.orExpr();
		}
		binLeft(sub, match) {
			let left = sub();
			for (;;) {
				const op = match();
				if (op === null) return left;
				const pos = this.peek().pos;
				this.next();
				left = {
					node: "binary",
					op,
					left,
					right: sub(),
					pos
				};
			}
		}
		orExpr() {
			return this.binLeft(() => this.xorExpr(), () => this.isKw("OR") ? "OR" : null);
		}
		xorExpr() {
			return this.binLeft(() => this.andExpr(), () => this.isKw("XOR") ? "XOR" : null);
		}
		andExpr() {
			return this.binLeft(() => this.notExpr(), () => this.isKw("AND") ? "AND" : null);
		}
		notExpr() {
			if (this.isKw("NOT")) {
				const pos = this.next().pos;
				return {
					node: "unary",
					op: "NOT",
					expr: this.notExpr(),
					pos
				};
			}
			return this.cmpExpr();
		}
		cmpExpr() {
			return this.binLeft(() => this.addExpr(), () => this.peek().kind === "op" && COMPARE.has(this.peek().value) ? this.peek().value : null);
		}
		addExpr() {
			return this.binLeft(() => this.mulExpr(), () => this.isOp("+") ? "+" : this.isOp("-") ? "-" : null);
		}
		mulExpr() {
			return this.binLeft(() => this.unaryExpr(), () => this.isOp("*") ? "*" : this.isOp("/") ? "/" : this.isKw("MOD") ? "MOD" : null);
		}
		unaryExpr() {
			if (this.isOp("-")) {
				const pos = this.next().pos;
				return {
					node: "unary",
					op: "NEG",
					expr: this.unaryExpr(),
					pos
				};
			}
			if (this.isOp("+")) {
				const pos = this.next().pos;
				return {
					node: "unary",
					op: "POS",
					expr: this.unaryExpr(),
					pos
				};
			}
			return this.primary();
		}
		primary() {
			const t = this.peek();
			if (t.kind === "num") {
				this.next();
				return {
					node: "num",
					value: t.num,
					real: t.real,
					pos: t.pos
				};
			}
			if (this.isKw("TRUE")) {
				this.next();
				return {
					node: "bool",
					value: true,
					pos: t.pos
				};
			}
			if (this.isKw("FALSE")) {
				this.next();
				return {
					node: "bool",
					value: false,
					pos: t.pos
				};
			}
			if (this.isOp("(")) {
				this.next();
				const e = this.expr();
				this.eatOp(")");
				return e;
			}
			if (t.kind === "ident") {
				this.next();
				if (this.isOp("(")) {
					this.next();
					const args = [];
					while (!this.isOp(")")) {
						args.push(this.expr());
						if (this.isOp(",")) this.next();
						else break;
					}
					this.eatOp(")");
					return {
						node: "call",
						name: t.value,
						args,
						pos: t.pos
					};
				}
				return this.accessChain({
					node: "var",
					name: t.value,
					pos: t.pos
				});
			}
			throw new StError(`unexpected '${t.value || t.kind}' in expression`, t.pos);
		}
	};
	function parse(toks) {
		return new Parser(toks).parse();
	}
	//#endregion
	//#region src/plc/interpreter.ts
	/** A builtin function block (TON/CTU/...). User FBs are `UserFbRef` objects. */
	function isFb(t) {
		return typeof t === "string" && FB_TYPES.includes(t);
	}
	/** A plain scalar type (anything that is neither a builtin FB nor a user FB instance). */
	function isScalarType(t) {
		return typeof t === "string" && !FB_TYPES.includes(t);
	}
	/** Thrown by EXIT, caught by the nearest enclosing loop's executor. */
	var EXIT_SIGNAL = Symbol("EXIT");
	/** Safety cap: a runaway WHILE/REPEAT or huge FOR throws instead of freezing the tab. */
	var MAX_LOOP_ITERATIONS = 1e6;
	var RANK = {
		BOOL: 0,
		SINT: 1,
		BYTE: 1,
		INT: 2,
		WORD: 2,
		DINT: 3,
		DWORD: 3,
		REAL: 4,
		LREAL: 5
	};
	function widen(a, b) {
		return RANK[a] >= RANK[b] ? a : b;
	}
	/** Scalar type of a user FB's readable output member, or null if there's no such output. */
	function fbOutputType(ref, member, fbDefs) {
		const def = fbDefs.get(ref.fb);
		if (!def) return null;
		const out = def.decls.find((d) => d.name === member && d.section === "VAR_OUTPUT");
		return out && isScalarType(out.type) ? out.type : null;
	}
	/** A function's body sees its inputs/locals plus an implicit return variable named after it. */
	function funcDecls(def) {
		return [...def.decls, {
			name: def.name,
			type: def.ret,
			init: null,
			section: "VAR_TEMP",
			pos: def.pos
		}];
	}
	/** Resolve the full data type of an expression (may be an aggregate for an intermediate place). */
	function inferType(e, scope) {
		switch (e.node) {
			case "num": {
				const t = e.real ? "REAL" : "INT";
				e.t = t;
				return t;
			}
			case "bool":
				e.t = "BOOL";
				return "BOOL";
			case "var": {
				const d = scope.env.get(e.name);
				if (!d) throw new StError(`undeclared variable '${e.name}'`, e.pos, e.name.length);
				if (isFb(d) || isUserFb(d)) throw new StError(`'${e.name}' is a function block; read an output like ${e.name}.Q`, e.pos, e.name.length);
				if (isScalarType(d)) e.t = d;
				return d;
			}
			case "member": {
				if (e.obj.node === "var") {
					const d = scope.env.get(e.obj.name);
					if (d && isFb(d)) {
						const mt = fbMemberType(d, e.field);
						if (!mt) throw new StError(`${d} has no output '${e.field}'`, e.pos, e.field.length);
						e.t = mt;
						return mt;
					}
					if (d && isUserFb(d)) {
						const mt = fbOutputType(d, e.field, scope.fbs);
						if (!mt) throw new StError(`'${d.fb}' has no readable output '${e.field}'`, e.pos, e.field.length);
						e.t = mt;
						return mt;
					}
				}
				const ot = inferType(e.obj, scope);
				if (!isStruct(ot)) throw new StError(`'.${e.field}' on a value that is not a struct`, e.pos, e.field.length);
				const f = scope.structs.get(ot.struct)?.fields.find((x) => x.name === e.field);
				if (!f) throw new StError(`'${ot.struct}' has no field '${e.field}'`, e.pos, e.field.length);
				if (isScalarType(f.type)) e.t = f.type;
				return f.type;
			}
			case "index": {
				const ot = inferType(e.obj, scope);
				if (!isArray(ot)) throw new StError("indexing a value that is not an array", e.pos);
				if (e.indices.length !== ot.dims.length) throw new StError(`array expects ${ot.dims.length} index(es), got ${e.indices.length}`, e.pos);
				for (const ix of e.indices) {
					const it = infer(ix, scope);
					if (it === "BOOL" || isReal(it)) throw new StError("array index must be an integer", ix.pos);
				}
				e.dims = ot.dims;
				if (isScalarType(ot.elem)) e.t = ot.elem;
				return ot.elem;
			}
			case "call": {
				const argTypes = e.args.map((a) => infer(a, scope));
				if (isBuiltinFunc(e.name)) {
					e.t = builtinResultType(e.name, argTypes, e.pos);
					return e.t;
				}
				const def = scope.funcs.get(e.name);
				if (!def) throw new StError(`unknown function '${e.name}'`, e.pos, e.name.length);
				const inputs = def.decls.filter((d) => d.section === "VAR_INPUT");
				if (e.args.length !== inputs.length) throw new StError(`'${e.name}' expects ${inputs.length} argument(s), got ${e.args.length}`, e.pos);
				e.t = def.ret;
				return def.ret;
			}
			case "unary": {
				const et = infer(e.expr, scope);
				if (e.op !== "NOT" && et === "BOOL") throw new StError(`unary ${e.op === "NEG" ? "-" : "+"} on BOOL`, e.pos);
				e.t = et;
				return et;
			}
			case "binary":
				e.t = inferBinary(e, scope);
				return e.t;
		}
	}
	/** Resolve an expression that must be a scalar value (operands, conditions, indices, args). */
	function infer(e, scope) {
		const t = inferType(e, scope);
		if (isArray(t)) throw new StError(e.node === "var" ? `'${e.name}' is an array; index it to read a value` : "an array must be indexed to read a value", e.pos);
		if (isStruct(t)) throw new StError(e.node === "var" ? `'${e.name}' is a struct; access a field to read a value` : "a struct field must be accessed to read a value", e.pos);
		return t;
	}
	function inferBinary(e, scope) {
		const lt = infer(e.left, scope);
		const rt = infer(e.right, scope);
		const op = e.op;
		if (op === "=" || op === "<>" || op === "<" || op === ">" || op === "<=" || op === ">=") return "BOOL";
		if (op === "AND" || op === "OR" || op === "XOR") {
			if (lt === "BOOL" && rt === "BOOL") return "BOOL";
			if (lt === "BOOL" || rt === "BOOL") throw new StError(`${op} mixes BOOL and non-BOOL operands`, e.pos);
			return widen(lt, rt);
		}
		if (lt === "BOOL" || rt === "BOOL") throw new StError(`arithmetic on BOOL operand`, e.pos);
		return isReal(lt) || isReal(rt) ? widen(isReal(lt) ? lt : "REAL", isReal(rt) ? rt : "REAL") : widen(lt, rt);
	}
	function checkStmt(s, scope, inLoop = false) {
		switch (s.node) {
			case "assign": {
				const t = s.target;
				if (t.node === "var") {
					const d = scope.env.get(t.name);
					if (d && (isFb(d) || isUserFb(d))) throw new StError(`cannot assign to function block '${t.name}'`, s.pos, t.name.length);
				}
				if (t.node === "member" && t.obj.node === "var") {
					const d = scope.env.get(t.obj.name);
					if (d && (isFb(d) || isUserFb(d))) throw new StError(`cannot assign to function-block output '${t.field}'`, s.pos);
				}
				const tt = inferType(t, scope);
				if (isArray(tt)) throw new StError(`cannot assign to array${t.node === "var" ? ` '${t.name}'` : ""} — index it (e.g. a[i] := ...)`, s.pos);
				if (isStruct(tt)) throw new StError(`cannot assign to struct${t.node === "var" ? ` '${t.name}'` : ""} — set a field (e.g. p.field := ...)`, s.pos);
				infer(s.value, scope);
				break;
			}
			case "fbcall": {
				const d = scope.env.get(s.inst);
				if (!d) throw new StError(`call to undeclared instance '${s.inst}'`, s.pos, s.inst.length);
				if (isFb(d)) for (const a of s.args) infer(a.value, scope);
				else if (isUserFb(d)) {
					const def = scope.fbs.get(d.fb);
					const inputs = new Set((def?.decls ?? []).filter((x) => x.section === "VAR_INPUT").map((x) => x.name));
					for (const a of s.args) {
						if (!inputs.has(a.name)) throw new StError(`'${d.fb}' has no input '${a.name}'`, a.pos, a.name.length);
						infer(a.value, scope);
					}
				} else throw new StError(`'${s.inst}' is not a function block`, s.pos, s.inst.length);
				break;
			}
			case "if":
				for (const br of s.branches) {
					infer(br.cond, scope);
					for (const st of br.body) checkStmt(st, scope, inLoop);
				}
				if (s.elseBody) for (const st of s.elseBody) checkStmt(st, scope, inLoop);
				break;
			case "case": {
				const st = infer(s.selector, scope);
				if (st === "BOOL" || isReal(st)) throw new StError("CASE selector must be an integer", s.pos);
				for (const clause of s.cases) for (const stmt of clause.body) checkStmt(stmt, scope, inLoop);
				if (s.elseBody) for (const stmt of s.elseBody) checkStmt(stmt, scope, inLoop);
				break;
			}
			case "for": {
				const vt = scope.env.get(s.varName);
				if (!vt) throw new StError(`undeclared loop variable '${s.varName}'`, s.pos, s.varName.length);
				if (!isScalarType(vt) || vt === "BOOL" || isReal(vt)) throw new StError("FOR loop variable must be an integer", s.pos);
				infer(s.from, scope);
				infer(s.to, scope);
				if (s.by) infer(s.by, scope);
				for (const stmt of s.body) checkStmt(stmt, scope, true);
				break;
			}
			case "while":
				infer(s.cond, scope);
				for (const stmt of s.body) checkStmt(stmt, scope, true);
				break;
			case "repeat":
				infer(s.cond, scope);
				for (const stmt of s.body) checkStmt(stmt, scope, true);
				break;
			case "exit":
				if (!inLoop) throw new StError("EXIT is only valid inside a loop", s.pos);
				break;
		}
	}
	/** Validate that every struct reference inside a data type resolves to a known type. */
	function validateDataType(t, structDefs, pos) {
		if (isStruct(t)) {
			if (!structDefs.has(t.struct)) throw new StError(`unknown type '${t.struct}'`, pos);
		} else if (isArray(t)) validateDataType(t.elem, structDefs, pos);
	}
	/** Build a POU's variable env, resolving identifier types and rejecting unknowns. */
	function buildEnv(decls, fbDefs, structDefs) {
		const env = /* @__PURE__ */ new Map();
		for (const d of decls) {
			if (env.has(d.name)) throw new StError(`duplicate declaration '${d.name}'`, d.pos, d.name.length);
			if (isUserFb(d.type)) {
				if (structDefs.has(d.type.fb)) d.type = { struct: d.type.fb };
				else if (!fbDefs.has(d.type.fb)) throw new StError(`unknown type '${d.type.fb}'`, d.pos, d.name.length);
			}
			if (!isFb(d.type) && !isUserFb(d.type)) validateDataType(d.type, structDefs, d.pos);
			env.set(d.name, d.type);
		}
		return env;
	}
	function checkBody(decls, body, scope) {
		for (const d of decls) if (d.init) infer(d.init, scope);
		for (const s of body) checkStmt(s, scope);
	}
	/** Names of functions called anywhere in a statement list (for recursion detection). */
	function collectCalledFunctions(body) {
		const out = /* @__PURE__ */ new Set();
		const ve = (e) => {
			switch (e.node) {
				case "call":
					out.add(e.name);
					e.args.forEach(ve);
					break;
				case "member":
					ve(e.obj);
					break;
				case "index":
					ve(e.obj);
					e.indices.forEach(ve);
					break;
				case "unary":
					ve(e.expr);
					break;
				case "binary":
					ve(e.left);
					ve(e.right);
					break;
				default: break;
			}
		};
		const vs = (s) => {
			switch (s.node) {
				case "assign":
					ve(s.target);
					ve(s.value);
					break;
				case "fbcall":
					s.args.forEach((a) => ve(a.value));
					break;
				case "if":
					s.branches.forEach((b) => {
						ve(b.cond);
						b.body.forEach(vs);
					});
					s.elseBody?.forEach(vs);
					break;
				case "case":
					ve(s.selector);
					s.cases.forEach((c) => c.body.forEach(vs));
					s.elseBody?.forEach(vs);
					break;
				case "for":
					ve(s.from);
					ve(s.to);
					if (s.by) ve(s.by);
					s.body.forEach(vs);
					break;
				case "while":
					ve(s.cond);
					s.body.forEach(vs);
					break;
				case "repeat":
					ve(s.cond);
					s.body.forEach(vs);
					break;
				case "exit": break;
			}
		};
		body.forEach(vs);
		return out;
	}
	/** Reject (in)direct function recursion at compile time — the interpreter assumes a DAG. */
	function checkNoFunctionRecursion(funcDefs) {
		const calls = /* @__PURE__ */ new Map();
		for (const [name, def] of funcDefs) calls.set(name, collectCalledFunctions(def.body));
		const state = /* @__PURE__ */ new Map();
		const visit = (name) => {
			const st = state.get(name) ?? 0;
			if (st === 2) return;
			if (st === 1) throw new StError(`recursive function '${name}'`, funcDefs.get(name).pos);
			state.set(name, 1);
			for (const callee of calls.get(name) ?? []) if (funcDefs.has(callee)) visit(callee);
			state.set(name, 2);
		};
		for (const name of funcDefs.keys()) visit(name);
	}
	/** The structs a struct contains by value (directly or as array elements). */
	function structDeps(def) {
		const deps = [];
		for (const f of def.fields) if (isStruct(f.type)) deps.push(f.type.struct);
		else if (isArray(f.type) && isStruct(f.type.elem)) deps.push(f.type.elem.struct);
		return deps;
	}
	/** Validate struct field types resolve, and reject by-value struct recursion (infinite size). */
	function checkStructDefs(structDefs) {
		for (const def of structDefs.values()) for (const f of def.fields) validateDataType(f.type, structDefs, f.pos);
		const state = /* @__PURE__ */ new Map();
		const visit = (name) => {
			const st = state.get(name) ?? 0;
			if (st === 2) return;
			if (st === 1) throw new StError(`recursive struct '${name}'`, structDefs.get(name).pos);
			state.set(name, 1);
			for (const dep of structDeps(structDefs.get(name))) if (structDefs.has(dep)) visit(dep);
			state.set(name, 2);
		};
		for (const name of structDefs.keys()) visit(name);
	}
	/** Lex, parse, and type-check every POU. Returns the annotated AST + def maps. Throws StError. */
	function parseAndCheck(source) {
		const ast = parse(lex(source));
		const structDefs = /* @__PURE__ */ new Map();
		for (const def of ast.typeDefs) {
			if (structDefs.has(def.name)) throw new StError(`duplicate type '${def.name}'`, def.pos, def.name.length);
			const seen = /* @__PURE__ */ new Set();
			for (const f of def.fields) {
				if (seen.has(f.name)) throw new StError(`duplicate field '${f.name}' in '${def.name}'`, f.pos, f.name.length);
				seen.add(f.name);
			}
			structDefs.set(def.name, def);
		}
		checkStructDefs(structDefs);
		const fbDefs = /* @__PURE__ */ new Map();
		for (const def of ast.fbDefs) {
			if (fbDefs.has(def.name) || structDefs.has(def.name)) throw new StError(`duplicate definition '${def.name}'`, def.pos, def.name.length);
			fbDefs.set(def.name, def);
		}
		const funcDefs = /* @__PURE__ */ new Map();
		for (const def of ast.funcDefs) {
			if (funcDefs.has(def.name) || fbDefs.has(def.name) || structDefs.has(def.name)) throw new StError(`duplicate definition '${def.name}'`, def.pos, def.name.length);
			funcDefs.set(def.name, def);
		}
		checkNoFunctionRecursion(funcDefs);
		const scopeFor = (env) => ({
			env,
			fbs: fbDefs,
			funcs: funcDefs,
			structs: structDefs
		});
		for (const def of ast.fbDefs) checkBody(def.decls, def.body, scopeFor(buildEnv(def.decls, fbDefs, structDefs)));
		for (const def of ast.funcDefs) {
			const decls = funcDecls(def);
			const env = buildEnv(decls, fbDefs, structDefs);
			for (const d of decls) if (isFb(d.type) || isUserFb(d.type)) throw new StError(`a function cannot contain function-block instances (use a FUNCTION_BLOCK): '${d.name}'`, d.pos, d.name.length);
			checkBody(decls, def.body, scopeFor(env));
		}
		const env = buildEnv(ast.decls, fbDefs, structDefs);
		checkBody(ast.decls, ast.body, scopeFor(env));
		return {
			ast,
			env,
			fbDefs,
			funcDefs,
			structDefs
		};
	}
	/** A user FUNCTION_BLOCK instance: a POU that retains its variable image across calls. */
	var UserFb = class {
		pou;
		constructor(pou) {
			this.pou = pou;
		}
		call(args, dt) {
			for (const k of Object.keys(args)) {
				const v = args[k];
				if (v !== void 0) this.pou.setInput(k, v);
			}
			this.pou.scan(dt);
		}
		read(member) {
			const v = this.pou.get(member);
			return v === void 0 ? 0 : v;
		}
		outputs() {
			return this.pou.outputs();
		}
	};
	/** Instantiate a user FB by name, guarding against (in)direct recursion. */
	function instantiate(name, fbDefs, funcs, structDefs, stack, pos) {
		if (stack.includes(name)) throw new StError(`recursive function block '${name}'`, pos);
		const def = fbDefs.get(name);
		if (!def) throw new StError(`unknown function block '${name}'`, pos);
		return new UserFb(buildPou(def.decls, def.body, fbDefs, funcs, structDefs, [...stack, name]));
	}
	/** Run a stateless function once with positional args, returning its result. */
	function runFunction(def, args, fbDefs, funcs, structDefs) {
		const pou = buildPou(funcDecls(def), def.body, fbDefs, funcs, structDefs, []);
		def.decls.filter((d) => d.section === "VAR_INPUT").forEach((d, i) => {
			if (i < args.length) pou.setInput(d.name, args[i]);
		});
		pou.scan(0);
		const v = pou.get(def.name);
		return v === void 0 ? def.ret === "BOOL" ? false : 0 : v;
	}
	/** Zero value for a data type: 0/false for scalars, nested arrays, zeroed struct records. */
	function zeroData(t, structDefs) {
		if (isArray(t)) return makeArray(t.dims, 0, t.elem, structDefs);
		if (isStruct(t)) {
			const rec = {};
			for (const f of structDefs.get(t.struct)?.fields ?? []) rec[f.name] = zeroData(f.type, structDefs);
			return rec;
		}
		return t === "BOOL" ? false : 0;
	}
	function makeArray(dims, k, elem, structDefs) {
		const d = dims[k];
		const n = d.hi - d.lo + 1;
		if (k === dims.length - 1) return Array.from({ length: n }, () => zeroData(elem, structDefs));
		return Array.from({ length: n }, () => makeArray(dims, k + 1, elem, structDefs));
	}
	/** Build a runnable POU from its declarations + body, instantiating nested FBs. */
	function buildPou(decls, body, fbDefs, funcs, structDefs, stack) {
		const env = /* @__PURE__ */ new Map();
		for (const d of decls) env.set(d.name, d.type);
		const vars = {};
		const fbs = {};
		/** Evaluate where a scalar is required (operands, conditions, indices) — checker-guaranteed. */
		function evalScalar(e) {
			return evalExpr(e);
		}
		/** Evaluate an expression; aggregate values are returned as live references (for mutation). */
		function evalExpr(e) {
			switch (e.node) {
				case "num": return e.value;
				case "bool": return e.value;
				case "var": {
					const v = vars[e.name];
					return v === void 0 ? 0 : v;
				}
				case "member": {
					if (e.obj.node === "var") {
						const fb = fbs[e.obj.name];
						if (fb) {
							if (fb instanceof UserFb) return fb.read(e.field);
							return fb[e.field] ?? 0;
						}
					}
					const obj = evalExpr(e.obj);
					if (obj && typeof obj === "object" && !Array.isArray(obj)) return obj[e.field] ?? 0;
					return 0;
				}
				case "index": {
					let cur = evalExpr(e.obj);
					const dims = e.dims ?? [];
					for (let k = 0; k < e.indices.length; k++) {
						if (!Array.isArray(cur)) return 0;
						const i = num(evalScalar(e.indices[k]));
						const d = dims[k];
						if (i < d.lo || i > d.hi) throw new StError(`array index ${i} out of bounds [${d.lo}..${d.hi}]`, e.pos);
						cur = cur[i - d.lo];
					}
					return cur ?? 0;
				}
				case "call": {
					const argv = e.args.map((a) => evalScalar(a));
					if (isBuiltinFunc(e.name)) return evalBuiltin(e.name, e.t, argv);
					const def = funcs.get(e.name);
					if (!def) return 0;
					return runFunction(def, argv, fbDefs, funcs, structDefs);
				}
				case "unary": {
					const v = evalScalar(e.expr);
					if (e.op === "NOT") return typeof v === "boolean" ? !v : wrap(e.t, ~num(v));
					if (e.op === "NEG") return wrap(e.t, -num(v));
					return num(v);
				}
				case "binary": return evalBinary(e);
			}
		}
		function evalBinary(e) {
			const op = e.op;
			const t = e.t;
			if (op === "=" || op === "<>" || op === "<" || op === ">" || op === "<=" || op === ">=") {
				const l = evalScalar(e.left);
				const r = evalScalar(e.right);
				switch (op) {
					case "=": return eq(l, r);
					case "<>": return !eq(l, r);
					case "<": return num(l) < num(r);
					case ">": return num(l) > num(r);
					case "<=": return num(l) <= num(r);
					case ">=": return num(l) >= num(r);
				}
			}
			if (op === "AND" || op === "OR" || op === "XOR") {
				const l = evalScalar(e.left);
				const r = evalScalar(e.right);
				if (t === "BOOL") {
					const a = bool$1(l);
					const b = bool$1(r);
					return op === "AND" ? a && b : op === "OR" ? a || b : a !== b;
				}
				const a = num(l);
				const b = num(r);
				return wrap(t, op === "AND" ? a & b : op === "OR" ? a | b : a ^ b);
			}
			const l = num(evalScalar(e.left));
			const r = num(evalScalar(e.right));
			if (isReal(t)) switch (op) {
				case "+": return l + r;
				case "-": return l - r;
				case "*": return l * r;
				case "/": return l / r;
				case "MOD": return l % r;
			}
			switch (op) {
				case "+": return wrap(t, l + r);
				case "-": return wrap(t, l - r);
				case "*": return t === "DINT" || t === "DWORD" ? wrap(t, Math.imul(l | 0, r | 0)) : wrap(t, l * r);
				case "/": return wrap(t, idiv(l, r));
				case "MOD": return wrap(t, imod(l, r));
			}
			throw new StError(`unsupported operator '${op}'`, e.pos);
		}
		function coerceScalar(type, v) {
			if (type === "BOOL") return bool$1(v);
			if (isInt(type)) return wrap(type, num(v));
			return num(v);
		}
		/** Write a coerced scalar into a place (var, struct field, or array element). */
		function assignPlace(target, c) {
			if (target.node === "var") {
				vars[target.name] = c;
				return;
			}
			if (target.node === "member") {
				const obj = evalExpr(target.obj);
				if (obj && typeof obj === "object" && !Array.isArray(obj)) obj[target.field] = c;
				return;
			}
			if (target.node === "index") {
				let cur = evalExpr(target.obj);
				const dims = target.dims ?? [];
				for (let k = 0; k < target.indices.length; k++) {
					if (!Array.isArray(cur)) return;
					const i = num(evalScalar(target.indices[k]));
					const d = dims[k];
					if (i < d.lo || i > d.hi) throw new StError(`array index ${i} out of bounds [${d.lo}..${d.hi}]`, target.pos);
					if (k === target.indices.length - 1) cur[i - d.lo] = c;
					else cur = cur[i - d.lo];
				}
			}
		}
		function execStmt(s, dt) {
			switch (s.node) {
				case "assign":
					assignPlace(s.target, coerceScalar(s.target.t, evalScalar(s.value)));
					break;
				case "fbcall": {
					const fb = fbs[s.inst];
					if (!fb) break;
					const a = {};
					for (const arg of s.args) a[arg.name] = evalScalar(arg.value);
					fb.call(a, dt);
					break;
				}
				case "if":
					for (const br of s.branches) if (bool$1(evalScalar(br.cond))) {
						for (const st of br.body) execStmt(st, dt);
						return;
					}
					if (s.elseBody) for (const st of s.elseBody) execStmt(st, dt);
					break;
				case "case": {
					const sel = num(evalScalar(s.selector));
					for (const clause of s.cases) if (clause.labels.some((l) => l.kind === "single" ? sel === l.value : sel >= l.lo && sel <= l.hi)) {
						for (const st of clause.body) execStmt(st, dt);
						return;
					}
					if (s.elseBody) for (const st of s.elseBody) execStmt(st, dt);
					break;
				}
				case "for": {
					const vt = env.get(s.varName);
					const to = num(evalScalar(s.to));
					const step = s.by ? num(evalScalar(s.by)) : 1;
					if (step === 0) throw new StError("FOR loop step is zero", s.pos);
					let count = 0;
					for (let i = num(evalScalar(s.from)); step > 0 ? i <= to : i >= to; i += step) {
						vars[s.varName] = coerceScalar(vt, i);
						try {
							for (const st of s.body) execStmt(st, dt);
						} catch (e) {
							if (e === EXIT_SIGNAL) break;
							throw e;
						}
						if (++count > MAX_LOOP_ITERATIONS) throw new StError("FOR loop exceeded its iteration limit", s.pos);
					}
					break;
				}
				case "while": {
					let count = 0;
					while (bool$1(evalScalar(s.cond))) {
						try {
							for (const st of s.body) execStmt(st, dt);
						} catch (e) {
							if (e === EXIT_SIGNAL) break;
							throw e;
						}
						if (++count > MAX_LOOP_ITERATIONS) throw new StError("WHILE loop exceeded its iteration limit", s.pos);
					}
					break;
				}
				case "repeat": {
					let count = 0;
					for (;;) {
						let exited = false;
						try {
							for (const st of s.body) execStmt(st, dt);
						} catch (e) {
							if (e === EXIT_SIGNAL) exited = true;
							else throw e;
						}
						if (exited || bool$1(evalScalar(s.cond))) break;
						if (++count > MAX_LOOP_ITERATIONS) throw new StError("REPEAT loop exceeded its iteration limit", s.pos);
					}
					break;
				}
				case "exit": throw EXIT_SIGNAL;
			}
		}
		for (const d of decls) if (isFb(d.type)) fbs[d.name] = makeFb(d.type);
		else if (isUserFb(d.type)) fbs[d.name] = instantiate(d.type.fb, fbDefs, funcs, structDefs, stack, d.pos);
		else if (isScalarType(d.type)) vars[d.name] = d.init ? coerceScalar(d.type, evalScalar(d.init)) : d.type === "BOOL" ? false : 0;
		else vars[d.name] = zeroData(d.type, structDefs);
		return {
			vars,
			fbs,
			scan(dt) {
				for (const s of body) execStmt(s, dt);
			},
			setInput(name, value) {
				const t = env.get(name);
				if (t && isScalarType(t)) vars[name] = coerceScalar(t, value);
			},
			get(name) {
				const v = vars[name];
				return typeof v === "number" || typeof v === "boolean" ? v : void 0;
			},
			outputs() {
				const out = [];
				for (const d of decls) if (d.section === "VAR_OUTPUT" && isScalarType(d.type)) {
					const v = vars[d.name];
					out.push([d.name, typeof v === "number" || typeof v === "boolean" ? v : 0]);
				}
				return out;
			}
		};
	}
	function compile(source) {
		const { ast, fbDefs, funcDefs, structDefs } = parseAndCheck(source);
		const pou = buildPou(ast.decls, ast.body, fbDefs, funcDefs, structDefs, []);
		return {
			inputs: ast.decls.filter((d) => d.section === "VAR_INPUT" && isScalarType(d.type)).map((d) => d.name),
			outputs: ast.decls.filter((d) => d.section === "VAR_OUTPUT" && isScalarType(d.type)).map((d) => d.name),
			get watch() {
				const out = {};
				for (const [k, v] of Object.entries(pou.vars)) if (typeof v === "number" || typeof v === "boolean") out[k] = v;
				for (const inst of Object.keys(pou.fbs)) {
					const fb = pou.fbs[inst];
					if (fb instanceof UserFb) for (const [m, v] of fb.outputs()) out[`${inst}.${m}`] = v;
					else {
						const rec = fb;
						for (const member of Object.keys(rec)) {
							const v = rec[member];
							if (typeof v === "boolean" || typeof v === "number") out[`${inst}.${member}`] = v;
						}
					}
				}
				return out;
			},
			setInput(name, value) {
				pou.setInput(name, value);
			},
			get(name) {
				return pou.get(name);
			},
			scan(dt) {
				pou.scan(dt);
			}
		};
	}
	function eq(l, r) {
		return typeof l === "boolean" || typeof r === "boolean" ? bool$1(l) === bool$1(r) : l === r;
	}
	//#endregion
	//#region src/plc/plcLink.ts
	/** In-process backend: compile an ST program and interpret it locally each tick. */
	var LocalPlcLink = class {
		prog;
		constructor(source) {
			this.prog = compile(source);
		}
		get inputs() {
			return this.prog.inputs;
		}
		get outputs() {
			return this.prog.outputs;
		}
		get watch() {
			return this.prog.watch;
		}
		step(inputs, dt) {
			for (const name of this.prog.inputs) {
				const v = inputs[name];
				if (v !== void 0) this.prog.setInput(name, v);
			}
			this.prog.scan(dt);
			const out = {};
			for (const name of this.prog.outputs) {
				const v = this.prog.get(name);
				if (v !== void 0) out[name] = v;
			}
			return out;
		}
	};
	//#endregion
	//#region src/plc/softPlc.ts
	var SoftPlc = class {
		link;
		/** Compile `source` into the served program. Throws on a compile error (same as LocalPlcLink). */
		constructor(source) {
			this.link = new LocalPlcLink(source);
		}
		meta() {
			return {
				t: "meta",
				inputs: [...this.link.inputs],
				outputs: [...this.link.outputs]
			};
		}
		/** Run one scan for the given input tags and return the resulting outputs + a watch snapshot. */
		step(inputs, dt) {
			return {
				t: "out",
				v: this.link.step(inputs, dt),
				watch: { ...this.link.watch }
			};
		}
		/** Snapshot of every program variable (inputs, outputs, internals) for a monitor/watch view. */
		watch() {
			return { ...this.link.watch };
		}
	};
	//#endregion
	//#region src/plc/embeddedPlc.ts
	var instances = /* @__PURE__ */ new Map();
	var nextHandle = 1;
	var lastError = "";
	function fail(message) {
		lastError = message;
	}
	function create(source) {
		try {
			const handle = nextHandle++;
			instances.set(handle, new SoftPlc(source));
			return handle;
		} catch (e) {
			fail(e instanceof Error ? e.message : String(e));
			return 0;
		}
	}
	function meta(handle) {
		const plc = instances.get(handle);
		if (!plc) {
			fail(`oip-plc: bad handle ${handle}`);
			return "{}";
		}
		const m = plc.meta();
		return JSON.stringify({
			inputs: m.inputs,
			outputs: m.outputs
		});
	}
	function step(handle, inputsJson, dt) {
		const plc = instances.get(handle);
		if (!plc) {
			fail(`oip-plc: bad handle ${handle}`);
			return "{}";
		}
		try {
			const inputs = JSON.parse(inputsJson);
			return JSON.stringify(plc.step(inputs, dt).v);
		} catch (e) {
			fail(e instanceof Error ? e.message : String(e));
			return "{}";
		}
	}
	/** JSON snapshot of EVERY program variable (inputs, outputs, internals) for online monitoring. */
	function watch(handle) {
		const plc = instances.get(handle);
		if (!plc) {
			fail(`oip-plc: bad handle ${handle}`);
			return "{}";
		}
		return JSON.stringify(plc.watch());
	}
	function destroy(handle) {
		instances.delete(handle);
	}
	/** Last error message; clears it so a host can poll after a 0/`{}` return. */
	function error() {
		const e = lastError;
		lastError = "";
		return e;
	}
	var OipPlc = {
		create,
		meta,
		step,
		watch,
		destroy,
		error
	};
	globalThis.OipPlc = OipPlc;
	//#endregion
	exports.OipPlc = OipPlc;
	exports.create = create;
	exports.destroy = destroy;
	exports.error = error;
	exports.meta = meta;
	exports.step = step;
	exports.watch = watch;
	return exports;
})({});
