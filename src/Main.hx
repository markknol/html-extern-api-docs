package;

import haxe.Http;
import haxe.xml.Fast;
import neko.Lib;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * ...
 * @author Mark Knol
 */
class Main 
{
	static function main() 
	{
		new Main();
	}
	
	public var totalClasses:Int = 0;
	public var replacedClasses:Int = 0;
	public var totalMethods:Int = 0;
	public var totalProperties:Int = 0;
	public var replacedMethods:Int = 0;
	public var replacedProperties:Int = 0;
	
	var newClassData:String;
	
	public function new()
	{
		for (file in FileSystem.readDirectory("out/"))
		{
			FileSystem.deleteFile("out/" + file);
		}
		
		FileSystem.createDirectory("out");
		var i = 0;
		for (fileName in FileSystem.readDirectory("html/"))
		{
			//if (i > 10) return;
			if (!FileSystem.isDirectory("html/" + fileName))
			{
				totalClasses++;
				var thing = fileName.split(".").shift();
				newClassData = File.getContent('html/${thing}.hx');
				
				if (newClassData.indexOf("\n@:native(") != -1) {
					thing = newClassData.split("\n@:native(\"").pop().split("\")").shift();
				}

				scrape(thing, Properties);
				scrape(thing, Methods);
				scrapeSummary(thing, Summary);
					
				File.saveContent('out/$thing.hx', newClassData);
				i ++;
			}
			
			if (i % 10 == 0)
			{
				trace("avg classes : " + (replacedClasses / totalClasses));
				trace("avg methods : " + (replacedMethods / totalMethods));
				trace("avg properties : " + (replacedProperties / totalProperties));
			}
		}
	}
	
	public function scrapeSummary(thing:String, type:MSDNType)
	{
		var msdnData = try
			Http.requestUrl('https://developer.mozilla.org/en-US/docs/Web/API/$thing?raw&$type')
		catch (e:Dynamic)
			null;
			
		
		if (msdnData == null || msdnData.length <= 2)
		{
			trace(thing, type, "failed");
			return false;
		}
		trace(thing, type, "success");
		
		msdnData = cleanDoc(msdnData);
		
		var query = "package js.html;";
		newClassData = newClassData.replace(query, query + "\n\n/**\n\t" + msdnData + "\n**/");
		return true;
	}
	
	public function scrape(thing:String, type:MSDNType)
	{
		var msdnData = try
			Http.requestUrl('https://developer.mozilla.org/en-US/docs/Web/API/$thing?raw&section=$type')
		catch(e:Dynamic)
			//try
				//Http.requestUrl('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/$thing?raw&section=$type')
			//catch(e:Dynamic)
				//try
					//Http.requestUrl('https://developer.mozilla.org/en-US/docs/Web/HTML/Element/$thing?raw&section=$type')
				//catch(e:Dynamic)
					null;
		
		if (msdnData == null || msdnData.length <= 5)
		{
			trace(thing, type, "failed");
			return false;
		}
		
		replacedClasses++;
		trace(thing, type, "success");
		
		switch(type)
		{
			case Methods:
				var classData = newClassData;
				var regexp = ~/function (.+?)(\()/ig;
				
				while (regexp.match(classData))
				{
					totalMethods++;
					var property = regexp.matched(1);
					var propertySearch = '<dt>{{domxref("$thing.$property(';
					if (msdnData.indexOf(propertySearch) > -1)
					{
						var splitted = msdnData.split(propertySearch).pop().split("</dd>").shift();
						var doc = cleanDoc(splitted.split('<dd>').pop());
						//trace(property, doc);
						replacedMethods++;
						
						var orig = 'function $property' + regexp.matched(2);
						newClassData = newClassData.replace(orig, "/**\n\t\t" + doc + "\n\t**/\n\t" + orig);
					}
					classData = regexp.matchedRight();
				}
				
				
			case Properties:
				var classData = newClassData;
				var regexp = ~/var (.+?)(\(|\s)/g;
				
				while (regexp.match(classData))
				{
					totalProperties++;
					var property = regexp.matched(1);
					var propertySearch = '<dt>{{domxref("$thing.$property")}}';
					if (msdnData.indexOf(propertySearch) > -1)
					{
						var splitted = msdnData.split(propertySearch).pop().split("</dd>").shift();
						var doc = cleanDoc(splitted.split('<dd>').pop());
						
						//trace(property, doc);
						var orig = 'var $property' + regexp.matched(2);
						newClassData = newClassData.replace(orig, "/**\n\t\t" + doc + "\n\t**/\n\t" + orig);
						replacedProperties++;
					}
					classData = regexp.matchedRight();
				}
			
			default:
		}
		return true;
	}
	
	function cleanDoc(value:String) 
	{
		value = ~/<(?:.|\n)*?>/gm.replace(value, '');
		value = ~/{{(.+?)\("(.+?)"(.+?)?}}/gm.replace(value, '`$2`');
		return value;
	}
}

@:enum abstract MSDNType(String) to String
{
	var Methods = "Methods";
	var Properties = "Properties";
	var Summary = "summary";
}