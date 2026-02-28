package moonchart.formats.fnf;

import moonchart.backend.FormatData;
import moonchart.backend.Timing;
import moonchart.backend.Util;
import moonchart.formats.BasicFormat;
import moonchart.formats.fnf.FNFGlobal;

enum abstract FNFNightEvent(String) from String to String
{
	var GF_SECTION = "FNF_NIGHT_GF_SECTION";
}

enum abstract FNFNightNoteType(String) from String to String
{
	var NIGHT_HEY_ANIM = "Hey!";
	var NIGHT_ALT_ANIM = "Alt Animation";
	var NIGHT_HURT_NOTE = "Hurt Note";
	var NIGHT_NO_ANIM = "No Animation";
	var NIGHT_GF_SING = "GF Sing";
  var NIGHT_DUAL_SING = 'Dual Note';
}

class FNFNight extends FNFNightBasic<NightJsonFormat>
{
	public static function __getFormat():FormatData
	{
		return {
			ID: FNF_NIGHT,
			name: "FNF (Night Engine)",
			description: "The Enhanced Expansion Modding Framework of FNF Psych 1.0.",
			extension: "json",
			formatFile: FNFLegacyNight.formatFile,
			hasMetaFile: POSSIBLE,
			metaFileExtension: "json",
			specialValues: [
        '?"strumlines":', '?"additionalChar":', '?"_editorLanes":', '?"charter":', '?"artist":',
        '?"format":', '?"offset":', '"needsVoices":',
        '?"gameOverChar":', '?"gameOverSound":', '?"gameOverLoop":', '?"gameOverEnd":',
        '?"disableNoteRGB":', '?"arrowSkin":', '?"splashSkin:',
        '?"gfVersion":', '?"gfSection":', '"stage":'],
			handler: FNFNight
		}
	}
}

@:private
@:noCompletion
class FNFNightBasic<T:NightJsonFormat> extends FNFLegacyNightBasic<T>
{
  public var sourceFormat:String = "unknown";

	public function new(?data:T)
	{
		super(data);
		this.formatMeta.supportsEvents = true;
		beautify = true;

		// Register FNF Night Engine note types
		noteTypeResolver.register(FNFNightNoteType.NIGHT_HEY_ANIM, BasicFNFNoteType.CHEER);
		noteTypeResolver.register(FNFNightNoteType.NIGHT_ALT_ANIM, BasicFNFNoteType.ALT_ANIM);
		noteTypeResolver.register(FNFNightNoteType.NIGHT_NO_ANIM, BasicFNFNoteType.NO_ANIM);
		noteTypeResolver.register(FNFNightNoteType.NIGHT_HURT_NOTE, BasicNoteType.MINE);
		noteTypeResolver.register(FNFNightNoteType.NIGHT_GF_SING, BasicFNFNoteType.GF_SING);
	}

	function resolvePsychEvent(event:BasicEvent):NightEvent
	{
		var values:Array<Dynamic> = Util.resolveEventValues(event);

		var value1:String = Std.string(values[0] ?? "");
		var value2:String = Std.string(values[1] ?? "");

		return [event.time, [[event.name, value1, value2]]];
	}

	// TODO: add GF_SECTION event inputs
	override function fromBasicFormat(chart:BasicChart, ?diff:FormatDifficulty):FNFNightBasic<T>
	{
		if (sourceFormat == "CNE") {
			var originalNoteTypes:Array<String> = [];
			var rawData:Dynamic = chart.data; // 아직 원본 상태인 chart.data 참조

			if (rawData != null && Reflect.hasField(rawData, "noteTypes")) {
				var types:Array<String> = cast Reflect.field(rawData, "noteTypes");
				if (types != null) {
					originalNoteTypes = types.copy(); // 원본 보존을 위해 복사본 생성
					// Codename 인덱스 규칙: 0번은 기본 노트용 공백
					if (originalNoteTypes.length > 0 && originalNoteTypes[0] != "")
						originalNoteTypes.insert(0, "");
				}
			}
		}
    
		this.offsetMustHits = false;
		var basic = super.fromBasicFormat(chart, diff);
		var song = basic.data.song;

    // Advenced Chart Parser

    // Notes
    if (sourceFormat == "CNE") {
			// Codename은 noteTypes를 data.noteTypes에 저장합니다.
			var codenameData:Dynamic = chart.data;
			var originalNoteTypes:Array<String> = cast (Reflect.field(codenameData, "noteTypes") ?? []);

			for (section in song.notes) {
				if (section.sectionNotes == null) continue;

				for (note in section.sectionNotes) {
					// Codename은 0:Dad, 1:BF, 2:GF / Night는 0:BF, 1:Dad, 2:GF
					final oldLane:Int = Std.int(note.lane); 
					final codenameStrumID:Int = Std.int(oldLane / 4);
					final internalLane:Int = oldLane % 4;

					var nightStrumID:Int = switch (codenameStrumID) {
						case 0: 1; // Dad -> Night ID 1
						case 1: 0; // BF  -> Night ID 0
						case 2: 2; // GF  -> Night ID 2
						default: codenameStrumID;
					};
					
					// 절대 레인으로 변환 (offsetMustHits가 false여야 함)
					note.lane = (nightStrumID * 4) + internalLane;
	
					var rawType:Dynamic = note.type; 
					if (rawType != null && (rawType is Int || rawType is Float)) {
						var typeIdx:Int = Std.int(rawType);
						// 이름이 있으면 이름으로, 없으면 숫자 문자열로 저장
						if (typeIdx > 0 && originalNoteTypes.length > typeIdx)
							note.type = originalNoteTypes[typeIdx]; 
						else if (typeIdx > 0)
							note.type = Std.string(typeIdx);
						else
							note.type = null;
					}
				}
      }
		}

    // Events
    if (sourceFormat == "CNE" && chart.data.events != null)
    {
      song.events = [];
      var tempEvents:Array<{time:Float, name:String, v1:String, v2:String}> = [];

      for (e in chart.data.events)
      {
        var name:String = e.name;
        var params:Array<Dynamic> = [];

        if (e.data != null) {
					if (Reflect.hasField(e.data, "array"))
						params = Reflect.field(e.data, "array");
					else if (Reflect.hasField(e.data, "params"))
						params = Reflect.field(e.data, "params");
					else if (Std.isOfType(e.data, Array))
						params = cast e.data;
        }

        var v1:String = "";
        var v2:String = "";

        if (params != null && params.length > 0) {
					// 일반적인 파라미터 분배 (기본값)
					var split = Math.ceil(params.length / 2);
					v1 = [for (i in 0...Std.int(split)) (params[i] == null ? "" : Std.string(params[i]))].join(",");
					v2 = [for (i in Std.int(split)...params.length) (params[i] == null ? "" : Std.string(params[i]))].join(",");
        
					// 특수 이벤트 처리 (기존 v1, v2를 덮어씌움)
					if (name == "Camera Movement") 
					{
						var codenameFocus:Int = Std.parseInt(Std.string(params[0] ?? "0"));
						var nightFocus:Int = switch (codenameFocus) 
						{
							case 0: 1; // Codename Dad(0) -> 내 엔진 Dad(1)
							case 1: 0; // Codename BF(1)  -> 내 엔진 BF(0)
							case 2: 2; // Codename GF(2)  -> 내 엔진 GF(2)
							default: codenameFocus;
						};
						
						v1 = Std.string(nightFocus);
						v2 = "";
					}

					if (name == "BPM Change") {
						var newBpm:Float = Std.parseFloat(v1);
						var curTime:Float = 0;
						var runningBpm:Float = song.bpm;
						for (sec in song.notes) {
							var crochet = (60 / runningBpm) * 1000;
							var duration = crochet * (sec.lengthInSteps / 4);
							if (e.time >= curTime && e.time < curTime + duration) {
								sec.changeBPM = true;
								sec.bpm = newBpm;
							}
							if (sec.changeBPM) runningBpm = sec.bpm;
							curTime += duration;
						}
					}
				}

        tempEvents.push({time: e.time, name: name, v1: v1, v2: v2});
      }

			// 2. 시간 순서대로 정렬
			tempEvents.sort((a, b) -> (a.time < b.time) ? -1 : (a.time > b.time ? 1 : 0));

			// 3. 같은 시간대의 이벤트를 그룹화하여 song.events에 삽입
			if (tempEvents.length > 0) {
				var lastTime:Float = -999.0;
				var currentGroup:Array<Dynamic> = [];

				for (e in tempEvents) {
					if (e.time != lastTime) {
						if (currentGroup.length > 0)
							song.events.push([lastTime, currentGroup]);
						lastTime = e.time;
						currentGroup = [];
					}
					currentGroup.push([e.name, e.v1, e.v2]);
				}
				// 마지막 그룹 추가
				if (currentGroup.length > 0)
					song.events.push([lastTime, currentGroup]);
			}
    } else if (chart.data.events != null) {
      var chartEvents = chart.data.events;
      var psychEvents:Array<NightEvent> = Util.makeArray(chartEvents.length);

      for (i in 0...chartEvents.length)
      {
        Util.setArray(psychEvents, i, resolvePsychEvent(chartEvents[i]));
      }

      song.events = psychEvents;
    }

    song.format = "night_v1_converted";
		song.gfVersion = chart.meta.extraData.get(PLAYER_3) ?? "gf";
		song.stage = chart.meta.extraData.get(STAGE) ?? "stage";

    // BasicChart에서 넘어온 레인 정보를 바탕으로 strumlines 배열을 빌드합니다.
    if (song.strumlines == null) {
      song.strumlines = [];
      // 기본적으로 플레이어(1)와 상대방(0) 라인은 생성
      song.strumlines.push({owner: "__opp", position: "LEFT", isPlayer: false, startData: 0, endData: 3});
      song.strumlines.push({owner: "__player", position: "RIGHT", isPlayer: true, startData: 4, endData: 7});
      
      // 만약 레인이 8 이상이면 추가 strumline 생성
      var maxLane = 0;
      for (sec in song.notes) for (n in sec.sectionNotes) if (n[1] > maxLane) maxLane = Std.int(n[1]);
      
      if (maxLane > 7) {
        song.strumlines.push({owner: "__gf", position: "CENTER", isPlayer: false, startData: 8, endData: 11});
      }
    }
    
    song._editorLanes = Std.int(Math.max(2, Math.ceil((song.strumlines.length))));

    song.artist = chart.meta.extraData.get(SONG_ARTIST) ?? null;
    song.charter = chart.meta.extraData.get(SONG_CHARTER) ?? null;

		return cast basic;
	}

	override function getEvents():Array<BasicEvent>
	{
		var events = super.getEvents();

		// Push GF section events
		var lastGfSection:Bool = false;
		forEachSection(data.song.notes, (section, startTime, endTime) ->
		{
			var psychSection:NightSection = cast section;

			var gfSection:Bool = (psychSection.gfSection ?? false);
			if (gfSection != lastGfSection)
			{
				events.push(makeGfSectionEvent(startTime, gfSection));
				lastGfSection = gfSection;
			}
		});

		// Push normal psych events
		for (baseEvent in data.song.events)
		{
			var time:Float = baseEvent.time;
			var pack:Array<PackedNightEvent> = baseEvent.pack;
			for (event in pack)
			{
				events.push({
					time: time,
					name: event.name,
					data: {
						VALUE_1: event.value1,
						VALUE_2: event.value2
					}
				});
			}
		}

		Timing.sortEvents(events);
		return events;
	}

	override function filterEvents(events:Array<BasicEvent>):Array<BasicEvent>
	{
		return super.filterEvents(events).filter((event) -> return event.name != GF_SECTION);
	}

	function makeGfSectionEvent(time:Float, gfSection:Bool):BasicEvent
	{
		return {
			time: time,
			name: GF_SECTION,
			data: {
				gfSection: gfSection
			}
		}
	}

	override function getChartMeta():BasicMetaData
	{
		var meta = super.getChartMeta();
		meta.extraData.set(PLAYER_3, data.song.gfVersion ?? data.song.player3);
		meta.extraData.set(STAGE, data.song.stage);
		return meta;
	}

	override function fromJson(data:String, ?meta:String, ?diff:FormatDifficulty):FNFNightBasic<T>
	{
		super.fromJson(data, meta, diff);

		// Support for Psych 1.0 format
		if (this.data.song is String)
		{
			this.data = {song: cast this.data};
			offsetMustHits = false;
		}

		updateEvents(this.data.song, (meta != null) ? this.meta.song : null);
		return this;
	}

	override function sectionBeats(?section:FNFLegacyNightSection):Float
	{
		var psychSection:Null<NightSection> = cast section;
		return psychSection?.sectionBeats ?? super.sectionBeats(section);
	}

	// Merge the events meta file and convert -1 lane notes to events
	function updateEvents(song:NightJsonFormat, ?events:NightJsonFormat):Void
	{
		var songNotes:Array<FNFLegacyNightSection> = song.notes;
		song.events ??= [];
		this.meta = null;

		if (events != null)
		{
			songNotes = songNotes.concat(events.notes ?? []);
			song.events = song.events.concat(events.events ?? []);
		}

		for (section in songNotes)
		{
			var sectionNotes:Array<FNFLegacyNightNote> = section.sectionNotes;

			for (i => note in sectionNotes)
			{
				if (note.lane <= -1)
				{
					song.events.push([note.time, [[note[2], note[3], note[4]]]]);
					Util.setArray(sectionNotes, i, null);
				}
			}

			var index:Int = sectionNotes.indexOf(null);
			while (index != -1)
			{
				sectionNotes.splice(index, 1);
				index = sectionNotes.indexOf(null);
			}
		}
	}
}

abstract NightEvent(Array<Dynamic>) from Array<Dynamic> to Array<Dynamic>
{
	public var time(get, never):Float;
	public var pack(get, never):Array<PackedNightEvent>;

	inline function get_time()
		return this[0];

	inline function get_pack()
		return this[1];
}

abstract PackedNightEvent(Array<String>) from Array<String> to Array<String>
{
	public var name(get, never):String;
	public var value1(get, never):String;
	public var value2(get, never):String;

  //public var params(get, never):Array<Dynamic>;

	inline function get_name()
		return this[0];

	inline function get_value1()
		return this[1];

	inline function get_value2()
		return this[2];

  //inline function get_params()
  //  return this[1];
}

typedef NightSection = FNFLegacyNightSection &
{
	?sectionBeats:Float,
	?gfSection:Bool // TODO: add as an event probably
}

typedef FNFLegacyNightFormat =
{
	song:String,
	notes:Array<FNFLegacyNightSection>,
	bpm:Float,
	needsVoices:Bool,
	speed:Float,
	validScore:Bool,
	player1:String,
	player2:String,
}

typedef FNFLegacyNightSection =
{
	mustHitSection:Bool,
	lengthInSteps:Int,
	sectionNotes:Array<FNFLegacyNightNote>,
	altAnim:Bool,
	changeBPM:Bool,
	bpm:Float
}

typedef NightChar =
{
	name:String,
	isPlayer:Bool,
	?x:Float,
	?y:Float,
	?location:String,
	?alpha:Float,
	?visible:Bool,
	?flipX:Bool
}

typedef NightStrum =
{
	?owner:String,
	?lane:Int,
	position:String,
  isPlayer:Bool,
	?alpha:Float,
	startData:Int,
	endData:Int,
	?noteHit:Dynamic->Void
}

typedef NightJsonFormat = FNFLegacyNightFormat &
{
  ?events:Array<NightEvent>,
	?gfVersion:String,
  offset:Float,
	stage:String,
  format:String,

  ?charter:String,
  ?artist:String,

	?gameOverChar:String,
	?gameOverSound:String,
	?gameOverLoop:String,
	?gameOverEnd:String,

	?disableNoteRGB:Bool,

	?arrowSkin:String,
	?splashSkin:String,

  ?additionalChar:Array<NightChar>,
  ?strumlines:Array<NightStrum>,
	?_editorLanes:Int,

	?player3:String
}

abstract FNFLegacyNightNoteType(Dynamic) from Int to Int from String to String from Dynamic to Dynamic {}

/*enum abstract FNFLegacyNightEvent(String) from String to String
	{
	var MUST_HIT_SECTION = "FNF_MUST_HIT_SECTION";
	var ALT_ANIM_SECTION = "FNF_ALT_ANIM_SECTION";
}*/
enum abstract FNFLegacyNightMetaValues(String) from String to String
{
	var PLAYER_1 = "FNF_P1";
	var PLAYER_2 = "FNF_P2";
	var PLAYER_3 = "FNF_P3";
	var STAGE = "FNF_STAGE";
	var NEEDS_VOICES = "FNF_NEEDS_VOICES";
	var VOCALS_OFFSET = "FNF_VOCALS_OFFSET";
}

class FNFLegacyNight extends FNFLegacyNightBasic<FNFLegacyNightFormat>
{
	/**
	 * The default must hit section value.
	 */
	public static var FNF_LEGACY_DEFAULT_MUSTHIT:Bool = true;

	public static inline var FNF_LEGACY_MUST_HIT_SECTION_EVENT:String = "FNF_MUST_HIT_SECTION";

	public static function __getFormat():FormatData
	{
		return {
			ID: FNF_LEGACY_NIGHT,
			name: "FNF (Legacy Night)",
			description: "The Legacy section-based FNF Night format.",
			extension: "json",
			formatFile: formatFile,
			hasMetaFile: FALSE,
			specialValues: ['_"notes":'],
			handler: FNFLegacyNight
		};
	}

	public static function formatFile(title:String, diff:String):Array<String>
	{
		diff = diff.trim().toLowerCase();
		var diffSuffix:String = (diff == "normal") ? "" : "-" + diff.replace(" ", "-");
		return [title.replace(" ", "-").trim().toLowerCase() + diffSuffix];
	}

	// TODO: Maybe some add some metadata for extrakey formats?
	public static inline function mustHitLane(mustHit:Bool, lane:Int):Int
	{
		if (lane > 7) return lane; // 8번 이상의 레인은 절대 좌표로 취급
    return (mustHit ? lane : (lane + 4) % 8);
	}

	public static inline function makeMustHitSectionEvent(time:Float, mustHit:Bool):BasicEvent
	{
		return {
			time: time,
			name: FNF_LEGACY_MUST_HIT_SECTION_EVENT,
			data: {
				mustHitSection: mustHit
			}
		}
	}

	public function new(?data:FNFLegacyNightFormat)
	{
		indexedTypes = true;
		super(data);
	}
}

@:private
@:noCompletion
class FNFLegacyNightBasic<T:FNFLegacyNightFormat> extends BasicJsonFormat<{song:T}, Dynamic>
{
	/**
	 * FNF (Legacy) handles sustains by being 1 step crochet behind their actual length.
	 * You can turn it off here if your legacy extended format doesn't have this quirk.
	 */
	public var offsetHolds:Bool = true;

	/**
	 * If to bake the song offset when loading from a basic format to the song's note times.
	 * Turn it off if your format has some sort of song offset value.
	 */
	public var bakedOffset:Bool = true;

	/**
	 * If to import the note types as ints rather than strings.
	 * Most legacy-branching formats use strings but legacy up to 0.2.7.1 used ints.
	 */
	public var indexedTypes:Bool = false;

	/**
	 * If to offset the note lanes depending on the mustHit section value.
	 * Most legacy-branching formats use this offset.
	 */
	public var offsetMustHits:Bool = true;

	/**
	 * Resolver for FNF note type IDs.
	 */
	public var noteTypeResolver(default, null):FNFNoteTypeResolver;

	public function new(?data:T)
	{
		super({timeFormat: MILLISECONDS, supportsDiffs: false, supportsEvents: false});
		this.data = {song: data};

		// Register FNF Legacy note types
		noteTypeResolver = FNFGlobal.createNoteTypeResolver();
		if (indexedTypes)
		{
			noteTypeResolver.register(0, BasicNoteType.DEFAULT);
			noteTypeResolver.register(1, BasicFNFNoteType.ALT_ANIM);
		}
	}

	public function resolveMustHitLane(mustHit:Bool, lane:Int):Int
	{
		return offsetMustHits ? FNFLegacyNight.mustHitLane(mustHit, lane) : lane;
	}

	override function fromBasicFormat(chart:BasicChart, ?diff:FormatDifficulty):FNFLegacyNightBasic<T>
	{
		var chartResolve = resolveDiffsNotes(chart, diff);
		var diff:String = chartResolve.diffs[0];
		var basicNotes:Array<BasicNote> = chartResolve.notes.get(diff);

		final meta = chart.meta;
		final initBpm = meta.bpmChanges[0].bpm;

		final notes:Array<FNFLegacyNightSection> = [];
		final measures = Timing.divideNotesToMeasures(basicNotes, chart.data.events, meta.bpmChanges);

		final lanesLength:Int = (meta.extraData.get(LANES_LENGTH) ?? 8) <= 7 ? 4 : 8;
		final offset:Float = meta.offset;

		// Take out must hit events
		chart.data.events = FNFGlobal.filterEvents(chart.data.events);

		var lastBpm = initBpm;
		var lastMustHit:Bool = FNFLegacyNight.FNF_LEGACY_DEFAULT_MUSTHIT;
		var nextMustHit:Null<Bool> = null;

		for (measure in measures)
		{
			var mustHit:Bool = lastMustHit;

			if (nextMustHit != null)
			{
				mustHit = nextMustHit;
				nextMustHit = null;
			}

			// Push must hit events
			for (event in measure.events)
			{
				// Check if measure has a must hit event
				if (FNFGlobal.isCamFocus(event))
				{
					var eventMustHit = FNFGlobal.resolveCamFocus(event) == BF;
					var eventTime = (event.time - measure.startTime);
					if (eventTime < measure.length / 2)
					{
						mustHit = eventMustHit;
						nextMustHit = null;
					}
					else
					{
						// Event happens too late, save it for the next measure (aprox)
						nextMustHit = eventMustHit;
					}
				}
			}

			// Create legacy section
			var section:FNFLegacyNightSection = {
				sectionNotes: [],
				mustHitSection: mustHit,
				lengthInSteps: Std.int(measure.stepsPerBeat * measure.beatsPerMeasure),
				altAnim: false,
				changeBPM: false,
				bpm: 0.0
			}

			lastMustHit = mustHit;

			// Section has a bpm change event (aprox)
			if (measure.bpm != lastBpm)
			{
				section.changeBPM = true;
				section.bpm = measure.bpm;
				lastBpm = measure.bpm;
			}

			final stepCrochet:Float = offsetHolds ? getHoldOffset(measure.bpm, measure.stepsPerBeat) : 0;

			// Push notes to section
			for (note in measure.notes)
			{
				/* final lane:Int = resolveMustHitLane(mustHit, (note.lane + 4 + lanesLength) % 8);
				final length:Float = note.length > 0 ? Math.max(note.length - stepCrochet, 0) : 0; */
				// AS-IS: final lane:Int = resolveMustHitLane(mustHit, (note.lane + 4 + lanesLength) % 8);
    
				// TO-BE: 레인이 8개 이상인 경우 % 8 연산을 하지 않음
				var rawLane = note.lane;
				final lane:Int = (rawLane < 8) ? resolveMustHitLane(mustHit, rawLane) : rawLane;
				
				final length:Float = note.length > 0 ? Math.max(note.length - stepCrochet, 0) : 0;
				final type:FNFLegacyNightNoteType = resolveBasicNoteType(note.type);

				final hasType = (type is String) ? (type != DEFAULT) : (type != 0);
				final fnfNote:FNFLegacyNightNote = hasType ? [note.time, lane, length, type] : [note.time, lane, length];

				if (bakedOffset)
				{
					fnfNote.time -= offset;
				}

				section.sectionNotes.push(fnfNote);
			}

			notes.push(section);
		}

		this.data = cast {
			song: {
				song: meta.title,
				bpm: initBpm,
				speed: meta.scrollSpeeds.get(diff) ?? Util.mapFirst(meta.scrollSpeeds) ?? 1.0,
				needsVoices: meta.extraData.get(NEEDS_VOICES) ?? true,
				validScore: true,
				player1: meta.extraData.get(PLAYER_1) ?? "bf",
				player2: meta.extraData.get(PLAYER_2) ?? "dad",
				notes: notes
			}
		};

		return this;
	}

	public function filterEvents(events:Array<BasicEvent>):Array<BasicEvent>
	{
		return FNFGlobal.filterEvents(events);
	}

	public function resolveBasicNoteType(type:BasicFNFNoteType):FNFLegacyNightNoteType
	{
		var noteType:FNFLegacyNightNoteType = noteTypeResolver.fromBasic(type);
		return (indexedTypes && !(noteType is Int)) ? 0 : noteType;
	}

	public function resolveNoteType(note:FNFLegacyNightNote):BasicFNFNoteType
	{
		return noteTypeResolver.toBasic(note.type);
	}

	function getHoldOffset(bpm:Float, stepsPerBeat:Float):Float
	{
		return Timing.stepCrochet(bpm, stepsPerBeat);
	}

	override function getNotes(?diff:String):Array<BasicNote>
	{
		var notes:Array<BasicNote> = [];
		var stepCrochet = offsetHolds ? getHoldOffset(data.song.bpm, 4) : 0;

		for (section in data.song.notes)
		{
			if (section.changeBPM && offsetHolds)
			{
				stepCrochet = getHoldOffset(section.bpm, 4);
			}

			for (note in section.sectionNotes)
			{
				// AS-IS: final lane:Int = resolveMustHitLane(section.mustHitSection, (note.lane + 4) % 8);
    
				// TO-BE: 8번 이상의 레인은 mustHitSection에 영향을 받지 않도록 보호
				var lane:Int = note.lane;
				if (lane < 8)
					lane = resolveMustHitLane(section.mustHitSection, lane);
				final length:Float = note.length > 0 ? note.length + stepCrochet : 0;
				final type:String = section.altAnim ? ALT_ANIM : resolveNoteType(note);

				notes.push({
					time: note.time,
					lane: lane,
					length: length,
					type: type
				});
			}
		}

		Timing.sortNotes(notes);

		return notes;
	}

	override function getEvents():Array<BasicEvent>
	{
		var events:Array<BasicEvent> = [];
		var lastMustHit:Bool = FNFLegacyNight.FNF_LEGACY_DEFAULT_MUSTHIT;

		// Push musthit events
		forEachSection(data.song.notes, (section, startTime, endTime) ->
		{
			if (section.mustHitSection != lastMustHit)
			{
				events.push(FNFLegacyNight.makeMustHitSectionEvent(startTime, section.mustHitSection));
				lastMustHit = section.mustHitSection;
			}
		});

		return events;
	}

	function forEachSection(sections:Array<FNFLegacyNightSection>, call:(FNFLegacyNightSection, Float, Float) -> Void)
	{
		var time:Float = 0;
		var crochet = Timing.measureCrochet(data.song.bpm, 4);

		for (section in sections)
		{
			if (section.changeBPM)
			{
				var beats:Float = sectionBeats(section);
				crochet = Timing.measureCrochet(section.bpm, beats);
			}

			call(section, time, time + crochet);
			time += crochet;
		}
	}

	function sectionBeats(?section:FNFLegacyNightSection):Float
	{
		return (section?.lengthInSteps ?? 16) / 4;
	}

	override function getChartMeta():BasicMetaData
	{
		var bpmChanges:Array<BasicBPMChange> = [];

		bpmChanges.push({
			time: 0.0,
			bpm: data.song.bpm,
			beatsPerMeasure: sectionBeats(data.song.notes[0]),
			stepsPerBeat: 4
		});

		forEachSection(data.song.notes, (section, startTime, endTime) ->
		{
			if (section.changeBPM)
				bpmChanges.push({
					time: startTime,
					bpm: section.bpm,
					beatsPerMeasure: sectionBeats(section),
					stepsPerBeat: 4
				});
		});

		// 최대 레인 값 찾기
    var maxLane = 7;
    for (section in data.song.notes) {
			for (note in section.sectionNotes) {
				if (note.lane > maxLane) maxLane = note.lane;
			}
    }

		return {
			title: data.song.song,
			bpmChanges: bpmChanges,
			offset: 0.0,
			scrollSpeeds: Util.fillMap(diffs, data.song.speed),
			extraData: [
				PLAYER_1 => data.song.player1,
				PLAYER_2 => data.song.player2,
				NEEDS_VOICES => data.song.needsVoices,
				LANES_LENGTH => maxLane + 1 // 동적으로 계산된 레인 수
			]
		}
	}

	public override function fromFile(path:String, ?meta:StringInput, ?diff:FormatDifficulty):FNFLegacyNightBasic<T>
	{
		if (meta != null)
		{
			var arr = meta.resolve();
			meta = arr;
			for (i in 0...arr.length)
				arr[i] = Util.getText(arr[i]);
		}

		return fromJson(Util.getText(path), meta, diff);
	}

	public override function fromJson(data:String, ?meta:StringInput, ?diff:FormatDifficulty):FNFLegacyNightBasic<T>
	{
		return cast super.fromJson(fixLegacyJson(data), meta, diff);
	}

	// Old json charts were hyper fucked with corrupted data
	function fixLegacyJson(rawJson:String):String
	{
		var split = rawJson.split("}");
		var pop = split.length - 1;

		if (split[pop].length > 0)
			split[pop] = "";

		rawJson = split.join("}");

		return rawJson;
	}
}

typedef FNFLegacyNightFormat =
{
	song:String,
	bpm:Float,
	speed:Float,
	needsVoices:Bool,
	validScore:Bool,
	player1:String,
	player2:String,
	notes:Array<FNFLegacyNightSection>
}

typedef FNFLegacyNightSection =
{
	mustHitSection:Bool,
	lengthInSteps:Int,
	sectionNotes:Array<FNFLegacyNightNote>,
	altAnim:Bool,
	changeBPM:Bool,
	bpm:Float
}

// TODO: FNF legacy and vslice (?) have the quirk of having lengths be 1 step crochet behind their actual length
// Should prob account for those, specially since formats like stepmania exist that require very specific hold lengths

abstract FNFLegacyNightNote(Array<Dynamic>) from Array<Dynamic> to Array<Dynamic>
{
	public var time(get, set):Float;
	public var lane(get, set):Int;
	public var length(get, set):Float;
	public var type(get, set):FNFLegacyNightNoteType;

	inline function get_time():Float
		return this[0];

	inline function get_lane():Int
		return this[1];

	inline function get_length():Float
		return this[2];

	inline function get_type():FNFLegacyNightNoteType
		return this[3];

	inline function set_time(v):Float
		return this[0] = v;

	inline function set_lane(v):Int
		return this[1] = v;

	inline function set_length(v):Float
		return this[2] = v;

	inline function set_type(v):FNFLegacyNightNoteType
		return this[3] = v;

	public static inline function make():FNFLegacyNightNote
	{
		return [0, 0, 0, ""];
	}
}
