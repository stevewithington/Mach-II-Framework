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

Configuration parameters

Scope
- The scope that the cache should be placed in.
- The default setting for "scope" is "application".
- Valid values are "application", "server" and "session".

ScopeKey
- The key place the cache in the choosen scope.
- Optional and by default the cache will be placed in scope._MachIICache.Hash(appKey & moduleName & cacheName)
- Rarely will this need to be used

Timespan
- Takes a string formatted like ColdFusion's createTimeSpan() function. The list is days, hours, minutes, seconds.
- Can also take "forever" for a non-expiring cache.
- The default is to cache for 1 hour.

CleanupIntervalInMinutes
- The interval of time in minutes in which to run the reap() method. Reap will
remove expired elements from the cache, but does not "refresh" the data. If an 
element is not available in the cache and an event-handler requests that data,
only that point will the data be "refreshed" and added back into the cache.
- The default setting for "cleanupIntervalInMinutes" is "3."
- Valid numeric value only.
- This attribute will rarely need to be changed.

Using all of the default settings will result in caching each element of data 
for 1 hour in the application scope. Expired cache elements will be cleaned up 
via reap() which is run every 3 minutes.

<property name="Caching" type="MachII.caching.CachingProperty">
      <parameters>
            <!-- Naming a default cache name is not required, but required if you do not want 
                 to specify the 'name' attribute in the cache command -->
            <parameter name="defaultCacheName" value="default" />
            <parameter name="default">
                  <struct>
                        <key name="type" value="MachII.caching.strategies.TimeSpanCache" />
                        <key name="scope" value="application" />
                        <key name="timespan" value="0,1,0,0"/><!-- Cache for 1 hour -->
						<key name="cleanupIntervalInMinutes" value="3" />
                  </struct>
            </parameter>
      </parameters>
</property>
--->
<cfcomponent
 	displayname="TimeSpanCache"
	extends="MachII.caching.strategies.AbstractCacheStrategy"
	output="false"
	hint="A caching strategy which uses a time span eviction policy.">

	<!---
	PROPERTIES
	--->
	<cfset variables.instance.timespan = "0,1,0,0" /><!--- Default to 1 hour --->
	<cfset variables.instance.scope = "application" />
	<cfset variables.instance.scopeKey = "" />
	<cfset variables.instance.cleanupInterval = 180000 /><!--- Internally we use ms --->
	
	<cfset variables.currentTickCount = "" />
	<cfset variables.lastCleanup = getCurrentTickCount() />
	<cfset variables.threadingAdapter = "" />
	<cfset variables.utils = CreateObject("component", "MachII.util.Utils").init() />
	
	<!---
	INITIALIZATION / CONFIGURATION
	--->
	<cffunction name="configure" access="public" returntype="void" output="false"
		hint="Configures the strategy.">

		<!--- Validate and set parameters --->
		<cfif isParameterDefined("timespan")>
			<cfif getParameter("timespan") NEQ "forever" AND ListLen(getParameter("timespan")) NEQ 4>
				<cfthrow type="MachII.caching.strategies.TimeSpanCache"
					message="Invalid timespan of '#getParameter("timespan")#'."
					detail="Timespan must be set to 'forever' or a list of 4 numbers (days, hours, minutes, seconds)." />
			<cfelse>
				<cfset setTimespan(getParameter("timespan")) />
			</cfif>
		</cfif>
		<cfif isParameterDefined("scope")>
			<cfif NOT ListFindNoCase("application,server,session", getParameter("scope"))>
				<cfthrow type="MachII.caching.strategies.TimeSpanCache"
					message="Invalid Scope of '#getParameter("scope")#'."
					detail="Use 'application', 'server' or 'session'." />
			<cfelse>
				<cfset setScope(getParameter("scope")) />
			</cfif>
		</cfif>
		<cfif isParameterDefined("scopeKey")>
			<cfif NOT Len(getParameter("scopeKey"))>
				<cfthrow type="MachII.caching.strategies.TimeSpanCache"
					message="Invalid ScopeKey of '#getParameter("ScopeKey")#'."
					detail="ScopeKey must have a length greater than 0 and be a valid struct key." />
			<cfelse>
				<cfset setScopeKey(getParameter("scopeKey")) />
			</cfif>
		<cfelseif isParameterDefined("generatedScopeKey")>
			<cfset setScopeKey(getParameter("generatedScopeKey")) />
		<cfelse>
			<cfset setScopeKey(REReplace(CreateUUID(), "[[:punct:]]", "", "ALL")) />
		</cfif>
		<cfif isParameterDefined("cleanupIntervalInMinutes")>
			<cfif NOT isNumeric(getParameter("cleanupIntervalInMinutes")) 
				OR getParameter("cleanupIntervalInMinutes") LTE 0>
				<cfthrow type="MachII.caching.strategies.TimeSpanCache"
					message="Invalid CleanupIntervalInMinutes of '#getParameter("cleanupIntervalInMinutes")#'."
					detail="CleanupIntervalInMinutes must be numeric and greater than 0." />
			<cfelse>
				<cfset setCleanupInterval(getParameter("cleanupIntervalInMinutes")) />
			</cfif>
		</cfif>

		<cfset setThreadingAdapter(variables.utils.createThreadingAdapter()) />
		
		<!--- Setup and clear the cache by running a flush() --->
		<cfset flush() />
	</cffunction>
	
	<!---
	PUBLIC FUNCTIONS
	--->
	<cffunction name="put" access="public" returntype="void" output="false"
		hint="Puts an element by key into the cache.">
		<cfargument name="key" type="string" required="true"
			hint="The key should not be a hashed key." />
		<cfargument name="data" type="any" required="true" />

		<cfset var dataStorage = getStorage() />
		<cfset var hashedKey = hashKey(arguments.key) />
		<cfset var cacheElement = StructNew() />
		<cfset var cacheUntilTimestamp = computeCacheUntilTimestamp() />
		
		<!--- Only increment if the element did not previous exist in the cache --->
		<cfif NOT StructKeyExists(dataStorage, hashedKey)>
			<cfset getCacheStats().incrementTotalElements(1) />
			<cfset getCacheStats().incrementActiveElements(1) />
		</cfif>
		
		<!--- Build the cache element --->
		<cfset cacheElement.data  = arguments.data />
		<cfset cacheElement.isStale = false />
		<cfset cacheElement.timestamp = cacheUntilTimestamp />
		
		<cfset dataStorage[hashedKey] = cacheElement />
	</cffunction>
	
	<cffunction name="get" access="public" returntype="any" output="false"
		hint="Gets en element by key from the cache. Returns 'null' if the key is not in the cache.">
		<cfargument name="key" type="string" required="true"
			hint="The key should not be a hashed key." />

		<cfset var dataStorage = getStorage() />
		<cfset var hashedKey = hashKey(arguments.key) />
		<cfset var cacheElement = "" />
		
		<cfset shouldCleanup() />
		
		<cfif keyExists(arguments.key)>
			<cfset cacheElement = dataStorage[hashedKey]>

			<cfif NOT cacheElement.isStale>
				<cfset getCacheStats().incrementCacheHits(1) />
				<cfreturn cacheElement.data />
			<cfelse>
				<cfset getCacheStats().incrementCacheMisses(1) />
			</cfif>
		<cfelse>
			<cfset getCacheStats().incrementCacheMisses(1) />
		</cfif>
	</cffunction>
	
	<cffunction name="flush" access="public" returntype="void" output="false"
		hint="Flushes all elements from the cache.">
		
		<cfset var dataStorage = getStorage() />
		
		<cfset StructClear(dataStorage) />		
	</cffunction>
	
	<cffunction name="keyExists" access="public" returntype="boolean" output="false"
		hint="Checks if an element exists by key in the cache.">
		<cfargument name="key" type="string" required="true"
			hint="The key should not be a hashed key." />

		<cfset var dataStorage = getStorage() />
		<cfset var hashedKey = hashKey(arguments.key) />
		<cfset var cacheElement = "" />

		<cfif NOT StructKeyExists(dataStorage, hashedKey)>
			<cfreturn false />
		<cfelse>
			<cfset cacheElement = dataStorage[hashedKey] />
			
			<cfif cacheElement.isStale>
				<cfreturn false />
			<cfelseif Javacast("long", cacheElement.timestamp - getCurrentTickCount()) LTE 0>
				<cfset removeByHashedKey(hashedKey) />
				<cfreturn false />
			<cfelse>
				<cfreturn true />
			</cfif>
		</cfif>
	</cffunction>
	
	<cffunction name="remove" access="public" returntype="void" output="false"
		hint="Removes data from the cache by key.">
		<cfargument name="key" type="string" required="true"
			hint="The key should not be a hashed key." />
		<cfset removeByHashedKey(hashKey(arguments.key)) />
	</cffunction>
	
	<cffunction name="reap" access="public" returntype="void" output="false"
		hint="Inspects the timestamps of cached elements and throws out the expired ones.">
			
		<cfset var timestamp = getCurrentTickCount() />
		<cfset var dataStorage = getStorage() />
		<cfset var keyArray = "" />
		<cfset var i = "" />
		
		<cflock name="#getNamedLockName("cleanup")#" type="exclusive" 
			timeout="1" throwontimeout="false">
			
			<!--- Reset the timestamp of the last cleanup --->
			<cfset variables.lastCleanup = timestamp />
			
			<cfset keyArray = StructKeyArray(dataStorage) />
			
			<!--- Cleanup --->
			<cfloop from="1" to="#ArrayLen(keyArray)#" index="i">
				<cftry>
					<cfif Javacast("long", dataStorage[keyArray[i]].timestamp - timestamp) LTE 0>
						<cfset removeByHashedKey(keyArray[i]) />
					</cfif>
					<cfcatch type="any">
						<!--- Do nothing --->
					</cfcatch>
				</cftry>
			</cfloop>
		</cflock>
	</cffunction>
	
	<!---
	PROTECTED FUNCTIONS - GENERAL
	--->
	<cffunction name="removeByHashedKey" access="private" returntype="void" output="false"
		hint="Removes data from the cache by hashed key.">
		<cfargument name="hashedKey" type="string" required="true"
			hint="The passed key needs to be a hashed key." />

		<cfset var dataStorage = getStorage() />
		<cfset var cacheElement = "" />

		<cfif StructKeyExists(dataStorage, arguments.hashedKey)>
			<cfset cacheElement = dataStorage[arguments.hashedKey] />
			
 			<cfif cacheElement.isStale>
				<cfset StructDelete(dataStorage, arguments.hashedKey, false) />
				<cfset getCacheStats().incrementEvictions(1) />
				<cfset getCacheStats().decrementTotalElements(1) />
				<cfset getCacheStats().decrementActiveElements(1) />
			<cfelse>
				<cfset cacheElement.isStale = true />
				<cfset getCacheStats().decrementActiveElements(1) />
			</cfif>
		</cfif>
	</cffunction>
	
	<cffunction name="shouldCleanup" access="private" returntype="void" output="false"
		hint="Cleanups the data storage.">
		
		<cfset var diffTimestamp = JavaCast("long", getCurrentTickCount() - getCleanupInterval()) />
		
		<cfif diffTimestamp - variables.lastCleanup GTE 0>
			<!--- Don't wait because an exclusive lock that has already been obtained
				indicates that a clean is in progress and we should not wait for the
				second check in the double-lock-check routine
				Setting the timeout to 0 indicates to wait indefinitely --->
			<cflock name="#getNamedLockName("cleanup")#" type="exclusive" 
				timeout="1" throwontimeout="false">
				<cfif diffTimestamp - variables.lastCleanup GTE 0>
					<cfif getThreadingAdapter().allowThreading()>
						<cfset getThreadingAdapter().run(this, "reap") />
					<cfelse>
						<cfset reap() />
					</cfif>
				</cfif>
			</cflock>
		</cfif>
	</cffunction>
	
	<!---
	PROTECTED FUNCTIONS - UTIL
	--->
	<cffunction name="hashKey" access="private" returntype="string" output="false"
		hint="Creates a hash from a key name.">
		<cfargument name="key" type="string" required="true" />
		<cfreturn Hash(UCase(Trim(arguments.key))) />
	</cffunction>
	
	<cffunction name="computeCacheUntilTimestamp" access="private" returntype="numeric" output="false"
		hint="Computes a cache until timestamp in ms.">

		<cfset var timestamp = getCurrentTickCount() />
		<cfset var timespan = getTimespan() />
		
		<cfif timespan EQ "forever">
			<!--- 864000000ms = 10 years --->
			<cfreturn Javacast("long", timestamp + 864000000) />
		<cfelse>
			<!--- 86400000ms = 1 day, 3600000ms = 1 hour, 60000ms = 1 minute, 1000ms = 1 second --->
			<cfreturn Javacast("long", timestamp 
						+ (ListGetAt(timespan, 4) * 1000) 
						+ (ListGetAt(timespan, 3) * 60000) 
						+ (ListGetAt(timespan, 2) * 3600000) 
						+ (ListGetAt(timespan, 1) * 86400000)) /> 
		</cfif>
	</cffunction>

	<cffunction name="getStorage" access="private" returntype="struct" output="false"
		hint="Gets a reference to the cache data storage.">
		<cfreturn StructGet(getScope() & "." & getScopeKey()) />
	</cffunction>
	
	<cffunction name="getNamedLockName" access="private" returntype="string" output="false"
		hint="Gets a named lock name based on choosen scope and other factors">
		<cfargument name="actionType" type="string" required="true" />
		
		<cfset var name = "_MachIITimeSpanCache_" & arguments.actionType & "_" & getScopeKey() />
		
		<!--- We don't want all sessions to share the same named lock
			since they will run reap independently whereas reap 
			done in the application or server scopes will only run once --->
		<cfif getScope() EQ "session">
			<!--- Cannot directly access session scope because most CFML
			engine will throw an error if sessions are disabled and you 
			directly access the session scope --->
			<cfset name = name & "_" & StructGet("session").sessionId />
		</cfif>

		<cfreturn name />
	</cffunction>

	<!---
	ACCESSORS
	--->
	<cffunction name="setTimespan" access="private" returntype="void" output="false">
		<cfargument name="timespan" type="string" required="true" />
		<cfset variables.instance.timespan = arguments.timespan />
	</cffunction>
	<cffunction name="getTimespan" access="public" returntype="string" output="false">
		<cfreturn variables.instance.timespan />
	</cffunction>

	<cffunction name="getCurrentTickCount" access="private" returntype="string" output="false"
		hint="Used internally for unit testing.">
		<cfif IsNumeric(variables.currentTickCount)>
			<cfreturn variables.currentTickCount />
		<cfelse>
			<cfreturn getTickCount() />
		</cfif>
	</cffunction>
	<cffunction name="setCurrentTickCount" access="public" returntype="void" output="false" 
		hint="Used internally for unit testing. Set to '' when you want to use the current tick count.">
		<cfargument name="currentTickCount" type="string" required="true" />
		<cfset variables.currentTickCount = arguments.currentTickCount />
	</cffunction>

	<cffunction name="setScope" access="private" returntype="void" output="false">
		<cfargument name="scope" type="string" required="true" />		
		<cfset variables.instance.scope = arguments.scope />
	</cffunction>
	<cffunction name="getScope" access="public" returntype="string" output="false">
		<cfreturn variables.instance.scope />
	</cffunction>

	<cffunction name="setScopeKey" access="private" returntype="void" output="false">
		<cfargument name="scopeKey" type="string" required="true" />
		<cfset variables.instance.scopeKey = arguments.scopeKey />
	</cffunction>
	<cffunction name="getScopeKey" access="private" returntype="string" output="false">
		<cfreturn variables.instance.scopeKey />
	</cffunction>

	<cffunction name="setCleanupInterval" access="private" returntype="void" output="false"
		hint="This converts the incoming minutes into ms.">
		<cfargument name="cleanupInterval" type="numeric" required="true" />		
		<cfset variables.instance.cleanupInterval = arguments.cleanupInterval * 60000 />
	</cffunction>
	<cffunction name="getCleanupInterval" access="public" returntype="numeric" output="false"
		hint="Cleanup interval in ms.">
		<cfreturn variables.instance.cleanupInterval />
	</cffunction>
	
	<cffunction name="setThreadingAdapter" access="private" returntype="void" output="false">
		<cfargument name="threadingAdapter" type="MachII.util.threading.ThreadingAdapter" required="true" />
		<cfset variables.threadingAdapter = arguments.threadingAdapter />
	</cffunction>
	<cffunction name="getThreadingAdapter" access="private" returntype="MachII.util.threading.ThreadingAdapter" output="false">
		<cfreturn variables.threadingAdapter />
	</cffunction>
	
</cfcomponent>