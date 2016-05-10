import basefs;
import std.json;
import std.string;
import std.algorithm;

import errno = core.stdc.errno;
import dfuse.fuse;

import std.conv;
import std.datetime;

debug import std.stdio;

class RedditTopicDirectory : RedditDirectory 
{
	this(string name, JSONValue topic)
	{
		auto time = SysTime(topic["created_utc"].floating.to!long.unixTimeToStdTime);
		super(name, octal!444, time);
		appendNode(new RedditFile("author", octal!444, time, topic["author"].str ~ "\n"));
		appendNode(new RedditFile("title", octal!444, time, topic["title"].str ~ "\n"));
		if(topic["selftext"].str.length > 0)
			appendNode(new RedditFile("selftext.md", octal!444, time, topic["selftext"].str ~ "\n"));
		appendNode(new RedditFile("permalink", octal!444, time, "http://reddit.com" ~ topic["permalink"].str ~ "\n"));
		if(topic["url"].str.length > 0)
			appendNode(new RedditFile("url", octal!444, time, topic["url"].str ~ "\n"));
	}
}


class SubRedditDirectory : RedditDirectory 
{
	this(string name)
	{
		super(name, octal!444, Clock.currTime);
	}

	override string[] readdir()
	{
		if(lastUpdate + 10.minutes < Clock.currTime)
			update();
		return super.readdir();
	}
	
	bool update()
	{
		debug writeln("updating ", name);
		nodes.clear();
		try {
			readSubReddit(this, "");
		} catch(Exception ex) {
			return false;
		} finally {
			addSubRedditType("hot");
			addSubRedditType("new");
			addSubRedditType("rising");
			addSubRedditType("controversial");
			addSubRedditType("top");
		}
		lastUpdate = Clock.currTime;
		return true;
	}
	
	void addSubRedditType(string type) 
	{
		try {
			auto dir = new RedditDirectory("." ~ type, octal!444, Clock.currTime);
			readSubReddit(dir, type);
			appendNode(dir);
		} catch(Exception ex) {
			debug writefln("error while loading r/%s/%s", name, type);
		}
	}
	
	void readSubReddit(RedditDirectory dir, string type)
	{
		import vibe.http.client;
		import vibe.stream.operations;

		requestHTTP("http://api.reddit.com/r/%s/%s".format(name, type),
			(scope req) {
				
			},
			(scope res) {
				res
					.bodyReader
					.readAllUTF8
					.parseJSON["data"]["children"]
					.array
					.map!(a => a["data"])
					.each!( data => dir.appendNode(
										new RedditTopicDirectory(data["permalink"]
																	.str
																	.split("/")[5], 
																 data)));
			});
	}

	SysTime lastUpdate;
}

class RemoveReditFile : RedditFile 
{
	this(string name, RedditRootDirectory rootDirectory)
	{
		super(name, octal!222, Clock.currTime, "");
		this.rootDirectory = rootDirectory;
	}
	
	override void write(in ubyte[] data) {
		import std.algorithm.mutation;

		auto str = (cast(string)data).removechars("\n\r");
		rootDirectory.nodes.remove(str);
		debug writeln("remove subreddit ", str);
	}

	RedditRootDirectory rootDirectory;
}

class AddSubReditFile : RedditFile 
{
	this(string name, RedditRootDirectory rootDirectory)
	{
		super(name, octal!222, Clock.currTime, "");
		this.rootDirectory = rootDirectory;
	}
	
	override void write(in ubyte[] data) 
	{
		import std.algorithm.mutation;
		auto str = (cast(string)data).removechars("\n\r"); //TODO: add more characters

		if(rootDirectory.hasNode(str))
			return;
		auto subReddit = new SubRedditDirectory(str);
		if(subReddit.update()) {
			rootDirectory.appendNode(subReddit);
			debug writeln("added subreddit ", str);
		} else {
			debug writeln("failed to add subreddit ", str);
		}
		
	}
		
	RedditRootDirectory rootDirectory;
}


class RedditRootDirectory : RedditDirectory 
{
	this()
	{
		super("/", octal!666, Clock.currTime);
		settingsDir = new RedditDirectory(".settings", octal!666, Clock.currTime);
		settingsDir.appendNode(new AddSubReditFile("add", this));
		settingsDir.appendNode(new RemoveReditFile("remove", this));
		appendNode(settingsDir);
	}
	
	override string[] readdir() 
	{
		return super.readdir();
	}
	
	RedditDirectory settingsDir;
}

class RedditFS : Operations
{
	this()
	{
		entryNode = new RedditRootDirectory();
	}
	
	override void getattr(const(char)[] path, ref stat_t s)
	{
		debug writeln("getattr ", path);
		traverse(path).getattr(s);
	}
	
	override string[] readdir(const(char)[] path)
	{
		debug writeln("readdir ", path);
		auto dir = cast(RedditDirectory)traverse(path);
		if(dir)
			return [".", ".."] ~ dir.readdir();
		throw new FuseException(errno.EOPNOTSUPP);
	}
	
	
	override ulong read(const(char)[] path, ubyte[] buf, ulong offset)
	{
		debug writeln("read ", path);
		auto file = cast(RedditFile)traverse(path);
		if(file) {
			auto data = file.read();
			buf[0..data.length] = data;
			return data.length;
		}
		throw new FuseException(errno.EOPNOTSUPP);
	}
	
	override int write(const(char)[] path, in ubyte[] buf, ulong offset)
	{
		debug writeln("write ", path);
		auto file = cast(RedditFile)traverse(path);
		if(file) {
			file.write(buf);
			return buf.length.to!int;
		}
		throw new FuseException(errno.EOPNOTSUPP);
	}
	
	Node traverse(const(char)[] path) 
	{
		import std.string;
		import std.algorithm;
		import std.array;
		
		return traverse(path.to!string.split("/").filter!(s => s.length > 0).array, entryNode);
	}
	
	Node traverse(string[] path, Node node)
	{
		if(path.length == 0)
			return node;
		
		auto dir = cast(RedditDirectory)node;
		if(dir) {
			if(dir.hasNode(path[0]))
				return traverse(path[1..$], dir.getNode(path[0]));
		}
		throw new FuseException(errno.ENOENT);
	}
	
	
	Node entryNode;
}
