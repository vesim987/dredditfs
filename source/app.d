import std.stdio;
import std.conv;

import dfuse.fuse;

import redditfs;
import basefs;


int main(string[] args)
{
	if (args.length != 2)
	{
		stderr.writeln("dredditfs <mount point>");
		return -1;
	}


	new Fuse("dredditfs", true, false)
		.mount(new RedditFS(), args[1], []);
    return 0;
}