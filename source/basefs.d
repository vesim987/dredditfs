import std.datetime;

import dfuse.fuse : FuseException;

import errno = core.stdc.errno;
import core.sys.posix.sys.stat;
import core.sys.posix.unistd;

class Node 
{
	this(string name, mode_t mode, SysTime time)
	{
		this.name = name;
		this.mode = mode;
		this.time = time;
	}

	abstract void getattr(ref stat_t s);
	abstract uint getSize();

	string name;
	mode_t mode;
	SysTime time;
}

class RedditFile : Node {
	this(string name, mode_t mode, SysTime time, string content)
	{
		super(name, mode | S_IFREG, time);
		this.content = content;
	}

	override void getattr(ref stat_t s)
	{
		s.st_size = getSize;
		s.st_uid = getuid;
		s.st_gid = getgid;
		s.st_nlink = 1;
		s.st_mtime = s.st_atime = s.st_ctime = time.toUnixTime();
		s.st_mode = mode;
	}

	void open(mode_t mode) {

	}

	override uint getSize()
	{
		return cast(uint)content.length;
	}

	ubyte[] read()
	{
		return cast(ubyte[])content;
	}

	void write(in ubyte[] data)
	{
		throw new FuseException(errno.EOPNOTSUPP);
	}


	string content;
}

class RedditDirectory : Node
{
	this(string name, mode_t mode, SysTime time)
	{
		super(name, mode | S_IFDIR, time);
	}

	override void getattr(ref stat_t s)
	{
		s.st_size = getSize;
		s.st_uid = getuid;
		s.st_gid = getgid;
		s.st_nlink = nodes.length;
		s.st_atime = 0;
		s.st_mtime = s.st_ctime = time.toUnixTime;
		s.st_mode = mode;
	}

	string[] readdir()
	{
		return nodes.keys;
	}

	override uint getSize()
	{
		import std.algorithm;
		return nodes.values.map!(node => node.getSize).sum();
	}

	bool hasNode(string name) 
	{
		return (name in nodes) != null;
	}

	Node appendNode(Node node) 
	{
		nodes[node.name] = node;
		return node;
	}

	Node getNode(string name)
	{
		return nodes[name];
	}

	Node[string] nodes;
}
