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
	
	public function new()
	{
		FileSystem.createDirectory("out");
		var i = 0;
		for (fileName in FileSystem.readDirectory("html/"))
		{
			//if (i > 10) return;
			if (!FileSystem.isDirectory("html/" + fileName))
			{
				totalClasses++;
				var thing = fileName.split(".").shift();
				try {
					scrape(thing, Properties);
					scrape(thing, Methods);
					trace(thing, "success");
					replacedClasses++;
				}catch (e:String) {
					trace(thing, "failed");
				}
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
	
	public function scrape(thing:String, type:MSDNType)
	{
		var msdnData = Http.requestUrl('https://developer.mozilla.org/en-US/docs/Web/API/$thing?raw&section='+type);
		
		switch(type)
		{
			case Methods:
				var classData = File.getContent('out/${thing}.hx');
				var newClassData = classData;
				var regexp = ~/function (.+?)\(/ig;
				
				while (regexp.match(classData))
				{
					totalMethods++;
					var property = regexp.matched(1);
					if (msdnData.indexOf('{{domxref("$thing.$property(') > -1)
					{
						var splitted = msdnData.split('{{domxref("$thing.$property(').pop().split("</dd>").shift();
						var doc = cleanDoc(splitted.split('<dd>').pop());
						//trace(property, doc);
						replacedMethods++;
						
						var orig = 'function $property(' + regexp.matched(2);
						newClassData = newClassData.replace(orig, "/**\n\t\t" + doc + "\n\t**/\n\t" + orig);
					}
					classData = regexp.matchedRight();
				}
				
				File.saveContent('out/$thing.hx', newClassData);
				
			case Properties:
				var classData = File.getContent('html/${thing}.hx');
				var newClassData = classData;
				var regexp = ~/var (.+?)(\(|\s)/g;
				
				while (regexp.match(classData))
				{
					totalProperties++;
					var property = regexp.matched(1);
					if (msdnData.indexOf('{{domxref("$thing.$property")}}') > -1)
					{
						var splitted = msdnData.split('{{domxref("$thing.$property")}}').pop().split("</dd>").shift();
						var doc = cleanDoc(splitted.split('<dd>').pop());
						
						//trace(property, doc);
						var orig = 'var $property' + regexp.matched(2);
						newClassData = newClassData.replace(orig, "/**\n\t\t" + doc + "\n\t**/\n\t" + orig);
						replacedProperties++;
					}
					classData = regexp.matchedRight();
				}
				
				
				File.saveContent('out/$thing.hx', newClassData);
		}
	}
	
	function cleanDoc(value:String) 
	{
		value = ~/<(?:.|\n)*?>/gm.replace(value, '');
		value = ~/{{(event|domxref|jsxref)\("(.+?)"(.+?)?}}/gm.replace(value, '`$2`');
		return value;
	}
}

@:enum abstract MSDNType(String) to String
{
	var Methods = "Methods";
	var Properties = "Properties";
}