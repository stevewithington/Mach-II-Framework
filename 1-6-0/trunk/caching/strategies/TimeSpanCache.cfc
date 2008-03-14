<!---
License:
Copyright 2008 GreatBizTools, LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Copyright: GreatBizTools, LLC
Author: Kurt Wiersma (kurt@mach-ii.com)
$Id$

Created version: 1.6.0
Updated version: 1.6.0

Notes:
<property name="Caching" type="MachII.caching.CachingProperty">
      <parameters>
            <!-- Naming a default cache name is not required, but required if you do not want 
                 to specify the 'cacheName' attribute in the cache command -->
            <parameter name="defaultCacheName" value="default" />
            <parameter name="default">
                  <struct>
                        <key name="type" value="MachII.caching.strategies.TimeSpanCache" />
                        <key name="scope" value="application" />
                        <key name="cacheFor" value="1" />
                        <key name="cacheUnit" value="hour" />
                  </struct>
            </parameter>
      </parameters>
</property>
--->
<cfcomponent
 	displayname="MachIICache"
	extends="MachII.caching.strategies.AbstractCacheStrategy"
	output="false"
	hint="A default caching strategy based on timespan of cached elements.">

	<!---
	PROPERTIES
	--->
	<cfset variables.cache = structNew() />
	<cfset variables.cache.data = structNew() />
	<cfset variables.cache.timestamps = structNew() />
	<cfset variables.cacheFor = 1 />
	<cfset variables.cacheForUnit = "hours" />
	<cfset variables.scope = "application" />
	<cfset variables.scopeKey = CreateUUID() />
	<cfset variables.utils = CreateObject("component", "MachII.util.Utils").init() />
	<cfset variables.cleanupDifference = -3 />
	<cfset variables.threadingAdapter = "" />
	<cfset variables.lastCleanup = createTimestamp() />
	
	<!---
	INITIALIZATION / CONFIGURATION
	--->
	<cffunction name="configure" access="public" returntype="void" output="false"
		hint="Configures the strategy.">

		<cfif isParameterDefined("cacheFor")>
			<cfset setCacheFor(getParameter("cacheFor")) />
		</cfif>
		<cfif isParameterDefined("cacheForUnit")>
			<cfset setCacheForUnit(getParameter("cacheForUnit")) />
		</cfif>
		<cfif isParameterDefined("scope")>
			<cfset setScope(getParameter("scope")) />
		</cfif>
		
		<cfset setThreadingAdapter(variables.utils.createThreadingAdapter()) />
		
	</cffunction>
	
	<!---
	PUBLIC FUNCTIONS
	--->
	<cffunction name="put" access="public" returntype="void" output="false"
		hint="Puts an element by key into the cache.">
		<cfargument name="key" type="string" required="true" hint="Doesn't need to be hashed" />
		<cfargument name="data" type="any" required="true" />

		<cfset var dataStorage = getCacheScope() />
		<cfset var hashedKey = hashKey(arguments.key) />
		
		<cfif NOT StructKeyExists(dataStorage.data, hashedKey)>
			<cfset dataStorage.data[hashedKey] = StructNew() />
			<cfset getCacheStats().incrementTotalElements(1) />
			<cfset getCacheStats().incrementActiveElements(1) />
		</cfif>
		<cfset dataStorage.data[hashedKey] = arguments.data />
		<cfset dataStorage.timestamps[createTimestamp() & "_" & hashedKey] = hashedKey />
		<cfset setCacheScope(dataStorage) />
	</cffunction>
	
	<cffunction name="get" access="public" returntype="any" output="false"
		hint="Gets en elementby key from the cache. Returns null if the key is not in the cache.">
		<cfargument name="key" type="string" required="true"
			hint="The key does not need to be hashed." />

		<cfset var dataStorage = getCacheScope() />
		<cfset var cache = dataStorage.data />
		<cfset var hashedKey = hashKey(arguments.key) />
		
		<cfset shouldCleanup() />
		
		<cfif keyExists(arguments.key)>
			<cfset getCacheStats().incrementCacheHits(1) />
			<cfreturn cache[hashedKey] />
		<cfelse>
			<cfset getCacheStats().incrementCacheMisses(1) />
		</cfif>
	</cffunction>
	
	<cffunction name="flush" access="public" returntype="void" output="false"
		hint="Flushes all elements from the cache.">
		
		<cfset var dataStorage = getCacheScope() />

		<cfset dataStorage.data = StructNew() />
		<cfset dataStorage.timestamps = StructNew() />
		<cfset setCacheScope(dataStorage) />
	</cffunction>
	
	<cffunction name="keyExists" access="public" returntype="boolean" output="false"
		hint="Checks if an element exists by key in the cache.">
		<cfargument name="key" type="string" required="true"
			hint="The key does not need to be hashed." />

		<cfset var dataStorage = getCacheScope() />
		<cfset var hashedKey = hashKey(arguments.key) />
		<cfset var findKey = StructKeyExists(dataStorage.data, hashedKey) />
		<cfset var timeStampKey = StructFindValue(dataStorage.timestamps, hashedKey, "one") />
		<cfset var diffTimestamp = createTimestamp(computeCacheUntilTimestamp()) />

		<cfif NOT findKey>
			<cfreturn false />
		<cfelseif (ListFirst(timeStampKey[1].key, "_") - diffTimestamp) GTE 0>
			<cfset remove(arguments.key) />
			<cfreturn false />
		<cfelse>
			<cfreturn true />
		</cfif>
	</cffunction>
	
	<cffunction name="remove" access="public" returntype="void" output="false"
		hint="Removes data from the cache by key.">
		<cfargument name="key" type="string" required="true"
			hint="The key does not need to be hashed." />

		<cfset var dataStorage = getCacheScope() />
		<cfset var cache = dataStorage.data />
		<cfset var hashedKey = hashKey(arguments.key) />
		<cfset var timeStampKey = "" />

		<cfif StructKeyExists(cache, hashedKey)>
			<cfset StructDelete(cache, hashedKey, false) />
			<cfset timeStampKey = StructFindValue(dataStorage.timestamps, hashedKey, "one") />
			<cfset StructDelete(dataStorage.timestamps, timeStampKey[1].key, false) />
			<cfset getCacheStats().incrementEvictions(1) />
			<cfset getCacheStats().decrementTotalElements(1) />
			<cfset getCacheStats().decrementActiveElements(1) />
		</cfif>
	</cffunction>
	
	<cffunction name="reap" access="public" returntype="void" output="false"
		hint="Inspects the timestamps of cached elements and throws out the expired ones.">
			
		<cfset var diffTimestamp = createTimestamp(computeCacheUntilTimestamp()) />
		<cfset var dataStorage = getCacheScope() />
		<cfset var dataTimestampArray = "" />
		<cfset var key = "" />
		<cfset var i = "" />
		<cfset var log = getLog() />
		
		<cflock name="_MachIITimeSpanCacheCleanup" type="exclusive" timeout="5" throwontimeout="false">
			
			<!--- Reset the timestamp of the last cleanup --->
			<cfset variables.lastCleanup = createTimestamp() />
				
			<!--- Get array of timestamps and sort --->
			<cfset dataTimestampArray = StructKeyArray(dataStorage.timestamps) />
			<cfset ArraySort(dataTimestampArray, "textnocase", "asc") />
			
			<!--- Cleanup --->
			<cfloop from="1" to="#ArrayLen(dataTimestampArray)#" index="i">
				<cftry>
					<cfif (diffTimestamp - ListFirst(dataTimestampArray[i], "_")) GTE 0>
						<!--- The order of the deletes is important as the timestamp may be
							around, but the data already deleted --->
						<cfset key = dataTimestampArray[i] />
						<cfset StructDelete(dataStorage.timestamps, key, false) />
						<cfset StructDelete(dataStorage.data, ListLast(key, "_"), false) />
					<cfelse>
						<cfbreak />
					</cfif>
					<cfcatch type="any">
						<!--- Ingore this error --->
					</cfcatch>
				</cftry>
			</cfloop>
		</cflock>
	</cffunction>
	 
	
	<!---
	PROTECTED FUNCTIONS
	--->
	<cffunction name="shouldCleanup" access="private" returntype="void" output="false"
		hint="Cleanups the data storage.">
		
		<cfset var diffTimestamp = createTimestamp(DateAdd("n", variables.cleanupDifference, now())) />
		<cfset var threadingAdapter = "" />
		
		<cfif (diffTimestamp - variables.lastCleanup) GTE 0>
		
			<cfset threadingAdapter = getThreadingAdapter() />
			
			<cflock name="_MachIITimespanCacheCleanup" type="exclusive" timeout="5" throwontimeout="false">
				<cfif (diffTimestamp - variables.lastCleanup) GTE 0>
					<cfif threadingAdapter.allowThreading()>
						<cfset threadingAdapter.run(this, "reap") />
					<cfelse>
						<cfset reap() />
					</cfif>
				</cfif>
			</cflock>
		</cfif>
	</cffunction>
	
	<cffunction name="hashKey" access="private" returntype="string" output="false"
		hint="Creates a hash from a key name.">
		<cfargument name="key" type="string" required="true" />
		<cfreturn Hash(UCase(arguments.key)) />
	</cffunction>
	
	<cffunction name="createTimestamp" access="private" returntype="string" output="false"
		hint="Creates a timestamp for use.">
		<cfargument name="time" type="date" required="false" default="#Now()#" />
		<cfreturn REReplace(arguments.time, "[ts[:punct:][:space:]]", "", "ALL") />
	</cffunction>
	
	<cffunction name="computeCacheUntilTimestamp" access="private" returntype="date" output="false"
		hint="Computes a cache until timestamp for this cache block.">
		
		<cfset var timestamp = Now() />
		<cfset var cacheFor = getCacheFor() />
		<cfset var unit = getCacheForUnit() />
		
		<cfif unit EQ "seconds">
			<cfset timestamp = DateAdd("s", cacheFor, timestamp) />
		<cfelseif unit EQ "minutes">
			<cfset timestamp = DateAdd("n", cacheFor, timestamp) />
		<cfelseif unit EQ "hours">
			<cfset timestamp = DateAdd("h", cacheFor, timestamp) />
		<cfelseif unit EQ "days">
			<cfset timestamp = DateAdd("d", cacheFor, timestamp) />
		<cfelseif unit EQ "forever">
			<cfset timestamp = DateAdd("y", 100, timestamp) />
		</cfif>
		
		<cfreturn timestamp />
	</cffunction>

	<cffunction name="getCacheScope" access="private" returntype="struct" output="false"
		hint="Gets the cache scope which is dependent on the storage location.">
		
		<cfset var storage = StructNew() />
		
		<cfif getScope() EQ "application">
			<cfset storage = variables.cache />
		<cfelseif getType() EQ "session">
			<cfset storage = StructGet("session") />
			
			<cfif NOT StructKeyExists(storage, "_MachIITimespanCache.#getScopeKey()#")>
				<cfset storage._MachIITimespanCache[getScopeKey()] = StructNew() />
			</cfif>
			
			<cfset storage = storage._MachIITimespanCache[getScopeKey()] />
		<cfelseif getType() EQ "server">
			<cfset storage = StructGet("server") />
			
			<cfif NOT StructKeyExists(storage, "_MachIITimespanCache.#getScopeKey()#")>
				<cfset storage._MachIITimespanCache[getScopeKey()] = StructNew() />
			</cfif>
			
			<cfset storage = storage._MachIITimespanCache[getScopeKey()] />
		</cfif>
		
		<cfreturn storage />
	</cffunction>
	
	<cffunction name="setCacheScope" access="private" returntype="void" output="false"
		hint="Sets the cache to the desired scope.">
		<cfargument name="cache" type="struct" required="true" />

		<cfif getScope() EQ "application">
			<cfset variables.cache = arguments.cache />
		<cfelseif getType() EQ "session">
			<cfset session._MachIITimespanCache[getScopeKey()] = arguments.cache />
		<cfelseif getType EQ "server">
			<cfset server._MachIITimespanCache[getScopeKey()] = arguments.cache />
		</cfif>
	</cffunction>

	<!---
	ACCESSORS
	--->
	<cffunction name="setCacheFor" access="private" returntype="void" output="false">
		<cfargument name="cacheFor" type="string" required="true" />

		<cfif NOT isNumeric(arguments.cacheFor)>
			<cfthrow type="MachII.caching.strategies.TimeSpanCache"
				message="Invalid CacheFor of '#arguments.cacheFor#'."
				detail="CacheFor must be numeric." />
		</cfif>

		<cfset variables.cacheFor = arguments.cacheFor />
	</cffunction>
	<cffunction name="getCacheFor" access="private" returntype="string" output="false">
		<cfreturn variables.cacheFor />
	</cffunction>

	<cffunction name="setCacheForUnit" access="private" returntype="void" output="false">
		<cfargument name="cacheForUnit" type="string" required="true" />
		
		<cfif NOT ListFindNoCase("seconds,minutes,hours,days,forever", arguments.cacheForUnit)>
			<cfthrow type="MachII.caching.strategies.TimeSpanCache"
				message="Invalid CacheForUnit of '#arguments.cacheForUnit#'."
				detail="Use 'seconds, 'minutes', 'hours', 'days' or 'forever'." />
		</cfif>

		<cfset variables.cacheForUnit = arguments.cacheForUnit />
	</cffunction>
	<cffunction name="getCacheForUnit" access="private" returntype="string" output="false">
		<cfreturn variables.cacheForUnit />
	</cffunction>
	
	<cffunction name="setScope" access="private" returntype="void" output="false">
		<cfargument name="scope" type="string" required="true" />
		
		<cfif NOT ListFindNoCase("application,server,session", arguments.scope)>
			<cfthrow type="MachII.caching.strategies.TimeSpanCache"
				message="Invalid Scope of '#arguments.scope#'."
				detail="Use 'application', 'server' or 'session'." />
		</cfif>
		
		<cfset variables.scope = arguments.scope />
	</cffunction>
	<cffunction name="getScope" access="private" returntype="string" output="false">
		<cfreturn variables.scope />
	</cffunction>
	
	<cffunction name="getScopeKey" access="private" returntype="string" output="false">
		<cfreturn variables.scopeKey />
	</cffunction>
	
	<cffunction name="setThreadingAdapter" access="private" returntype="void" output="false">
		<cfargument name="threadingAdapter" type="MachII.util.threading.ThreadingAdapter" required="true" />
		<cfset variables.threadingAdapter = arguments.threadingAdapter />
	</cffunction>
	<cffunction name="getThreadingAdapter" access="private" returntype="MachII.util.threading.ThreadingAdapter" output="false">
		<cfreturn variables.threadingAdapter />
	</cffunction>
	
</cfcomponent>