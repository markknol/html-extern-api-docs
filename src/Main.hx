package;

import haxe.Http;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
	Haxe HTML extern API documentation MDN wiki processor factory macroless bean visitor-facade application aware injection decorator layer.

	Example MDN url <https://developer.mozilla.org/en-US/docs/Web/API/window>
	Can be loaded "raw" like this, and a certain section <https://developer.mozilla.org/en-US/docs/Web/API/window?raw&section=Properties>

	What I do is load the file content of "js.html.Window.hx" of the in-directory, find its properties/methods, search in the MDN document for same properties/methods, search its documentation, put it back in the Haxe file, store in out-directory. 
	I also get+inject the summary of the MDN page.
	
	@see MDN document parameters: https://developer.mozilla.org/en-US/docs/MDN/Contribute/Tools/Document_parameters
 
	@author Mark Knol
 */
class Main
{
	// base out folder
	static inline var OUT_FOLDER = "_output_documented_html/";
	
	// base in folder
	static inline var IN_FOLDER = "../haxe/std/js/html/";
	
	// all scraped data will be stored here. When running for second time it will use data from disk
	static inline var DATA_FOLDER = "_mdn-docs-cache/";
	
	static inline var MDN_URL = "https://developer.mozilla.org/en-US/docs/Web/API/";

	static var nameAliases = [
		'ConsoleInstance' => 'Console'
	];
	
	
	static function main() new Main();


	// store file temporary here, to allow multiple edits
	private var processedHaxeFile:String;
	
	// stats of collected data. 
	private var stats = {
		classes: {
			total: 0,
			replaced: 0,
		},
		methods: {
			total: 0,
			replaced: 0,
		}, 
		properties: {
			total: 0,
			replaced: 0,
		},
		summaries: {
			total: 0,
			replaced: 0,
		}
	}

	public function new()
	{
		// create cache data folder
		FileSystem.createDirectory(DATA_FOLDER);
		
		
		var basePack = "js.html";
		
		// process base package
		process(IN_FOLDER, OUT_FOLDER, basePack);
		
		// process sub packages
		for (pack in ["audio", "idb", "rtc", "svg", "webgl"])
		{
			process('${IN_FOLDER}${pack}/', '${OUT_FOLDER}${pack}/', '$basePack.$pack');
		}
		
		logStats();
	}
	
	private function process(inFolder:String, outFolder:String, pack:String)
	{
		trace('processing $pack ..');
		
		// clean output
		FileSystem.createDirectory(outFolder);
		for (file in FileSystem.readDirectory(outFolder))
			if (!FileSystem.isDirectory(outFolder + file)) 
				FileSystem.deleteFile(outFolder + file);
		
		// read through all extern files
		for (fileName in FileSystem.readDirectory(inFolder))
		{
			if (!FileSystem.isDirectory(inFolder + fileName))
			{
				var thing = fileName.split(".").shift();
				if (thing == '') continue;

				stats.classes.total++;

				processedHaxeFile = File.getContent('$inFolder${thing}.hx');

				// extract native type name
				var nativeMetaSearch = "\n@:native(\"";
				if (processedHaxeFile.indexOf(nativeMetaSearch) != -1) thing = processedHaxeFile.split(nativeMetaSearch).pop().split("\")").shift();

				// alias 'thing'
				if (nameAliases[thing] != null) {
					thing = nameAliases[thing];
				}
				
				// process properties
				var foundProps = processThing(thing, Properties, pack);
				
				// process methods
				var foundMethods = processThing(thing, Methods, pack);
				
				// process summary
				var foundSummary = processThing(thing, Summary, pack, foundProps || foundMethods);

				if (foundProps || foundMethods || foundSummary) stats.classes.replaced ++;
				
				// finally, save in out folder, no matter if something actually is replaced
				File.saveContent('$outFolder$fileName', processedHaxeFile);
			}
		}
	}
	
	private function getMDNData(thing:String, type:MSDNType, needCopyright:Bool = false)
	{
		// get mdn url. 
		var url = switch(type)
		{
			case Methods, Properties:
				if  (thing == 'WebGLRenderingContext' || thing == 'WebGL2RenderingContext') {
					// WebGL pages don't have methods and properties sections
					// Instead, pull everything and search through for methods
					'$MDN_URL$thing?raw';	
				} else {
					'$MDN_URL$thing?raw&section=$type';
				}
				
			case Summary:
				'$MDN_URL$thing?raw&$type';
		}
		
		// request data from disk, otherwise download it
		var data = 
			if (FileSystem.exists('$DATA_FOLDER$thing-$type')) 
				File.getContent('$DATA_FOLDER$thing-$type')
			else 
				try{
					trace('Requesting MDN data for "$thing" at "$url"');
					Http.requestUrl(url);
				} catch (e:Dynamic)
					null;
			
		if (data == null || data.length <= 5)
		{
			// store a empty file
			//trace(thing, type, "failed");
			File.saveContent('$DATA_FOLDER$thing-$type', "fail");
			return null;
		}
		
		// store on disk
		File.saveContent('$DATA_FOLDER$thing-$type', data);
		return data;
	}

	private function processThing(thing:String, type:MSDNType, pack:String, needCopyright:Bool = false)
	{
		var mdnData = getMDNData(thing, type);
		if (mdnData == null) return false;
		//trace(thing, type, "success");
		
		inline function getAsString(v:String) return (v != null && v.length > 0) ? v : "";
		
		var found = false;
		switch (type)
		{
			case Methods:
				
				// haxiomic: added support for matching methods with metadata
				var regexp = ~/(\/\*\* (.+?) \*\/\n\t)?((@:?[^\n]+\s*)*(static\s+)?function (.+?)(\())/ig;
				// replace extern file content with replaced data
				processedHaxeFile = regexp.map(processedHaxeFile, function(regexp) 
				{
					stats.methods.total ++;
					var methodName = regexp.matched(6);
					
					function search(query:String) {
						if (mdnData.indexOf(query) > -1)
						{
							found = true;
							
							// get doc of this method. seach for data in next dd-element
							var doc = cleanDoc(mdnData.split(query).pop().split('</dd>').shift().split('<dd>').pop());
							
							stats.methods.replaced ++;
							
							// get api docs of extern file method, if any. just prepend it for now.
							var origDoc = getAsString(regexp.matched(2));
							origDoc = (origDoc.length > 0) ? '\n\t\t$origDoc' : '';
							
							return '\n\t/**\n\t\t$doc$origDoc\n\t**/\n\t' + regexp.matched(3);
						}
						return null;
					}

					for (query in [
						'<dt>{{domxref("$thing.$methodName(',
						'<dt>{{domxref("${classCase(thing)}.$methodName(',
						'<dt>$methodName(',
						'<dt><code>$methodName(',
					]) {
						var result = search(query);
						if (result != null) return result;
					}
					
					return getAsString(regexp.matched(1)) + regexp.matched(3);
				});
				
				
			case Properties:
				// haxiomic: added support for matching methods with metadata
				var regexp = ~/(\/\*\* (.+?) \*\/\n\t)?((@:?[^\s]+\s*)*(static\s+)?var (.+?)(\(|\s))/g;
				// replace extern file content with replaced data
				
				processedHaxeFile = regexp.map(processedHaxeFile, function(regexp) 
				{
					stats.properties.total ++;
					var property = regexp.matched(6);
					
					function search(query:String) {
						if (mdnData.indexOf(query) > -1)
						{
							found = true;
							// get doc of this property. seach for data in next dd-element
							var doc = cleanDoc(mdnData.split(query).pop().split('</dd>').shift().split('<dd>').pop());
							
							stats.properties.replaced ++;
							
							// get api docs of extern file property, if any. just prepend it for now.
							var origDoc = getAsString(regexp.matched(2));
							origDoc = (origDoc.length > 0) ? '\n\t\t$origDoc' : '';
							
							return '\n\t/**\n\t\t$doc$origDoc\n\t**/\n\t' + regexp.matched(3);
						}
						return null;
					}

					for (query in [
						'<dt>{{domxref("$thing.$property")}}',
						'<dt>{{domxref("${classCase(thing)}.$property")}}',
						'<dt>$property<',
						'<dt><code>$property<',
					]) {
						var result = search(query);
						if (result != null) return result;
					}
					
					return getAsString(regexp.matched(1)) + regexp.matched(3);
				});

				
			case Summary:
				mdnData = cleanDoc(mdnData);
				stats.summaries.total ++; 
				
				if (mdnData.length > 2 || needCopyright) 
				{
					stats.summaries.replaced ++;
					
					
					if (mdnData.length > 2) 
					{
						found = true;
						mdnData += "\n\n\t";
					}
					
					// put summary after package definition
					var query = new EReg("(package " + pack + ";)([\\r\\n\\t\\s]{1,6})", "ig");
					
					var copyright = 'Documentation [$thing]($MDN_URL$thing) by [Mozilla Contributors]($MDN_URL$thing$$history), licensed under [CC-BY-SA 2.5](https://creativecommons.org/licenses/by-sa/2.5/).';
					var credits = '@see <$MDN_URL$thing>';
					// replace extern file content with replaced data
					processedHaxeFile = query.replace(processedHaxeFile, '$1\n\n/**\n\t$mdnData$copyright\n\n\t$credits\n**/\n');
				}
		}
		
		return found;
	}

	private function cleanDoc(value:String)
	{
		inline function replaceSpecialWikiMarkup(value:String) 
		{
			return value
				.replace("{{deprecated_inline()}}", "<em>(deprecated)</em>")
				.replace("{{obsolete_inline}}", "<em>(deprecated)</em>")
				.replace("{{experimental_inline}}", "<em>(experimental)</em>");
		}
		
		// when there is a table, we keep all html tags, because markdown/html doesnt mix well
		if (value.indexOf("<table")>-1)
		{
			// when there is a table, keep all relevant html
			value = stripTags(value, ["pre", "code", "table", "tr", "td", "br"]);

			value = replaceSpecialWikiMarkup(value);
			
			// remove wiki markup. dont mix html and markdown
			value = ~/{{(.+?)\("(.+?)"(.+?)?}}/gm.replace(value, '<code>$2</code>');
		}
		else
		{
			// if there is no table, convert stuff to markdown
			value = ~/<\/?(code)>/ig.replace(value, "`");
			value = ~/<\/?(br)\/?>/ig.replace(value, "\n");
			
			// remove all other html tags
			value = ~/<(?:.|\n)*?>/gm.replace(value, '');

			value = replaceSpecialWikiMarkup(value);
			
			// remove wiki markup, replace with code
			value = ~/{{(.+?)\(("|')(.+?)("|')(.+?)?}}/gm.replace(value, '`$3`');
		}
		
		// remove some html-entities. 
		value = value.replace("&lt;", "").replace("&gt;", "");
		
		// return indented
		return value.split("\n").join("\n\t\t");
	}

	inline function stripTags(value:String, keepTags:Array<String>)
	{
		var tags = [];
		for (tag in keepTags)
		{
			tags.push(tag);
			tags.push("/" + tag);
		}

		if (tags.length == 0)
		{
			return ~/<(\s*\/?)[^>]+>/g.replace(value, "");
		}
		else
		{
			var ereg = new EReg("<(?!(" + tags.join("|") + ")\\s*\\/?)[^>]+>", "g" );
			return ereg.replace(value, '' );
		}
	}

	private function classCase(value: String) {
		return value.charAt(0).toUpperCase() + value.substring(1);
	}
	
	private function logStat(stat:{total:Int, replaced:Int})
	{
		return Std.int(stat.replaced / stat.total * 100) + '%  (${stat.replaced}/${stat.total})';
	}
	
	private function logStats() 
	{
		trace('-- STATS --');
		trace('classes found: ${logStat(stats.classes)}');
		
		trace('methods added: ${logStat(stats.methods)}');
		trace('properties added: ${logStat(stats.properties)}');
		trace('summaries added: ${logStat(stats.summaries)}');
	}
}

// capitals of values are different here on purpose
@:enum abstract MSDNType(String) to String
{
	var Methods = "Methods";
	var Properties = "Properties";
	var Summary = "summary";
}