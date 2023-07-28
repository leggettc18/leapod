/*
 * SPDX-License-Identifier: LGPL-3.0.or-later
 * SPDX-FileCopyrightText: 2021 Christopher Leggett <chris@leggett.dev>
 */

namespace Leopod {

    errordomain LeopodUpdateError {
        NETWORK_ERROR, EMPTY_ADDRESS_ERROR;
    }

    class FeedParser {

        private Gee.ArrayList<string> queue = new Gee.ArrayList<string> ();

        private SoupClient soup_client = null;

        public FeedParser () {
            soup_client = new SoupClient ();
        }

        /*
         * Creates a new podcast by iterating through the queue and finding appropriate
         * key/value pairs
         */
        private Podcast create_podcast_from_queue (string? fallback_feed_uri) {

            // Create the new podcast object
            Podcast podcast = null;
            ObservableArrayList<Episode> episodes =
                new ObservableArrayList<Episode> ();

            bool found_podcast_title = false;
            bool found_podcast_link = false;
            bool found_cover_art = false;
            bool found_main_description = false;
            bool found_license = false;
            bool type_found = false;

            string name = null;
            string feed_uri = null;
            string podcast_description = null;
            string remote_art_uri = null;
            License license = License.UNKNOWN;
            MediaType content_type = MediaType.UNKNOWN;

            int i = 0;

            while (i < queue.size) {
                string current = queue[i];
                // Title can be ambigous, so only accept the first one
                if (current == "title" && found_podcast_title == false) {
                    i++;
                    name = queue[i];
                    found_podcast_title = true;
                    i++;
                }
                else if (current == "new-feed-url" && found_podcast_link == false) {

                    i++;
                    feed_uri = queue[i];
                    found_podcast_link = true;
                    i++;
                }

                // Most feeds use the new-feed-url enclosure, but if not we have to check links manually
                else if ((current == "link" || current == "atom:link") && found_podcast_link == false) {
                    i++;
                    string href = null;
                    bool store_ref = false;

                    // There are six fields, but we can't assume any order
                    for (int n = 0; n < 6; n++) {
                        if (queue[i + n] == "application/rss+xml") {
                            store_ref = true;
                        }
                        if (queue[i + n] == "href") {
                            href = queue[i + n + 1];
                        }
                    }

                    if (store_ref) {
                        feed_uri = href;
                        found_podcast_link = true;
                    }


                }

                else if (current == "description" && found_main_description == false) {
                    i++;
                    podcast_description = queue[i];
                    found_main_description = true;
                    i++;
                }
                else if (current == "image") {

                    if (queue[i + 2] == "href") {
                        // When there is an iTunes image, queue[i + 1] is empty
                        if (queue[i + 1] == "" || found_cover_art == false) {
                            i += 3;
                            remote_art_uri = queue[i];
                        }
                    } else if (found_cover_art == false) {
                        while (queue[i] != "url") {
                            i++;
                        }

                        i++;
                        remote_art_uri = queue[i];
                    }

                    found_cover_art = true;
                    i++;
                }
                else if (current == "license") {
                    i++;
                    if (queue[i].up ().contains ("CREATIVE")) {
                        license = License.CC;
                    }
                    found_license = true;
                    i++;
                }

                // We've found an episode!!
                else if (current == "item") {

                    // Create a new episode
                    string title = null;
                    string uri = null;
                    string description = null;
                    string guid = null;
                    string date_released = null;
                    string link = null;

                    string next_item_in_queue = null;

                    while (next_item_in_queue != "item" && i < queue.size - 1) {
                        i++;
                        next_item_in_queue = queue[i];

                        if (next_item_in_queue == "title") {
                            i++;
                            title = queue[i];
                        }
                        else if (next_item_in_queue == "enclosure") {
                            bool uri_found = false;

                            // Because different podcasts enclose information differently,
                            // we must individually search for both the uri and the type
                            while (uri_found != true || type_found != true) {
                                // Look at next item
                                i++;

                                if (queue[i] == "url") {

                                    i++;
                                    uri = queue[i];
                                    uri_found = true;

                                }
                                else if (queue[i] == "type") {
                                    i++;

                                    string typestring = queue[i].slice (0, 5);
                                    if (content_type == MediaType.UNKNOWN) {
                                        if (typestring == "audio") {
                                            content_type = MediaType.AUDIO;
                                        }
                                        else if (typestring == "video") {
                                            content_type = MediaType.VIDEO;
                                        }
                                        else {
                                            content_type = MediaType.UNKNOWN;
                                        }

                                    }

                                    type_found = true;
                                }
                            }

                        }
                        else if (next_item_in_queue == "pubDate") {
                            i++;

                            date_released = queue[i];
                            //episode.set_datetime_from_pubdate ();

                        }
                        else if (next_item_in_queue == "summary") {
                            // Save the summary as description if we haven't found a description yet.
                            // Subsequent descriptions will overwrite this.
                            if (description.char_count () == 0) {
                                i++;
                                description = queue[i];
                            }
                        }
                        else if (next_item_in_queue == "description") {
                            i++;
                            description = queue[i];
                        } else if (next_item_in_queue == "guid") {
                            i++;
                            guid = queue[i];
                        } else if (next_item_in_queue == "link") {
                            i++;
                            link = queue[i];
                        }
                    }


                    // Add the new episode to the podcast
                    Episode episode = new Episode(
                        title, uri, date_released, description, guid, link
                    );
                    episodes.add(episode);

                }

                // Otherwise, simply increment and keep going
                else {
                    i++;
                }
            }

            if (feed_uri == null) {
                feed_uri = fallback_feed_uri;
            }

            podcast = new Podcast(
                name, podcast_description, feed_uri, remote_art_uri,
                license, content_type
            );

            info ("%s %s %s %s", name, podcast_description, feed_uri, remote_art_uri);
            
            podcast.add_episodes (episodes);

            return podcast;
        }

        /*
         * Finds only the podcast description and returns it as a string
         */
        public string? find_description_from_file (string path) throws GLib.Error {

            string description = "";

            // Call the Xml.Parser to parse the file, which returns an unowned reference
            Xml.Doc* doc = Xml.Parser.parse_file (path);

            // Make sure that it didn't return a null reference
            if (doc == null) {
                warning ("Error opening file %s", path);
                return null;
            }

            // Get the root node
            Xml.Node* root = doc->get_root_element ();

            // Make sure that it didn't return a null reference, either
            if (root == null) {

                // If it did, free the document manually (since unowned)
                delete doc;
                warning ("The XML file '%s' is empty", path);
                return null;
            }

            // Parse the root node, which in turn will cause all nodes and properties to be parsed
            parse_node (root);

            string next_item_in_queue = null;

            for (int i = 0; i < queue.size - 1; i++) {

                next_item_in_queue = queue[i];

                if (next_item_in_queue == "summary") {
                    i++;
                    description = queue[i];
                    return description;

                }
                else if (next_item_in_queue == "description") {
                    i++;
                    description = queue[i];
                    return description;
                }
            }

            // Free the document
            delete doc;

            return null;
        }

        /*
         * Parses a given XML file and returns a new podcast object if able to parse it properly
         */
        public Podcast? get_podcast_from_file (string path) throws GLib.Error {
            /*
                For reference: podcast rss feeds typically have the structure:
                0. Rss
                    1. Channel
                        2. Title
                        2. Link
                        2. General
                            3. Explicit
                            3. Image URL
                            3. Etc..
                        2. ID1 (Episode)
                        2. ID2 (Episode)
                        2. ...
            */

            // Call the Xml.Parser to parse the file, which returns an unowned reference
            Xml.Doc* doc;
            if (SoupClient.valid_http_uri (path)) {
                try {
                    doc = XmlUtils.parse_string (soup_client.request_as_string (HttpMethod.GET, path));
                } catch (GLib.Error e) {
                    warning ("Failed to get podcast. %s", e.message);
                    return null;
                }
            } else {
                doc = Xml.Parser.parse_file (path);
            }

            // Make sure that it didn't return a null reference
            if (doc == null) {
                warning ("Error parsing xml file %s", path);
                return null;
            }

            // Get the root node
            Xml.Node* root = doc->get_root_element ();

            // Make sure that it didn't return a null reference, either
            if (root == null) {
                // If it did, free the document manually (since unowned)
                delete doc;
                warning ("The XML file '%s' is empty", path);
                return null;
            }

            // Parse the root node, which in turn will cause all nodes and properties to be parsed
            parse_node (root);

            // Create the podcast object and set it as parent to child episodes
            Podcast podcast = null;

            if (root->name == "feed") {
                info ("parsing atom feed");
                podcast = create_podcast_from_queue_atom (root);
            } else {
                info ("parsing rss feed");
                podcast = create_podcast_from_queue (path);
                info ("parsed rss feed for %s", podcast.name);
            }

            if (podcast.name.length < 1) {
                warning ("Something went wrong during podcast parsing. Abort.");
                return null;
            }

            foreach (Episode child in podcast.episodes) {
                child.parent = podcast;

            }

            if (podcast.coverart_uri == null || podcast.coverart_uri.length < 1) {
                podcast.coverart_uri = "resource:///com/github/leggettc18/leopod/banner.png";
            }

            if (podcast.feed_uri == null || podcast.feed_uri.length < 1) {
                podcast.feed_uri = path;
            }

            // Free the document
            delete doc;

            return podcast;
        }

        /*
         * Parses an OPML file and returns an array listing each feed discovered within
         */
        public string[] parse_feeds_from_OPML (string path, bool raw_data = false) throws LeopodLibraryError {  // vala-lint=naming-convention
            var feeds = new Gee.ArrayList<string> ();

            queue.clear ();

            // Call the Xml.Parser to parse the file, which returns an unowned reference

            /*
            // TODO:
            // I believe this is outdate code, but I'm leaving it commented out in case it is necessary.
            // I can test it with the Ubuntu UK feed, if memory serves correctly

            Xml.Doc* doc;

            // If bracket character is in the path, assume it's the raw data, not a path
            if (path.contains("<")) {
                doc = Xml.Parser.parse_memory (path, path.length);
            } else {
                doc = Xml.Parser.parse_file (path);
            }
            */

            Xml.Doc* doc;

            if (!raw_data) {
				doc = Xml.Parser.parse_file (path);
        	} else {
        		doc = Xml.Parser.parse_memory (path, path.length);
        	}

            // Make sure that it didn't return a null reference
            if (doc == null) {
                throw new LeopodLibraryError.IMPORT_ERROR (
                    _ ("Selected file doesn't appear to contain podcast subscriptions.")
                );
            }

            // Get the root node
            Xml.Node* root = doc->get_root_element ();

            // Make sure that it didn't return a null reference, either
            if (root == null) {

                // If it did, free the document manually (since unowned)
                delete doc;
                warning (_ ("Selected file seems to be empty."));
                return feeds.to_array ();
            }

            // Parse the root node, which in turn will cause all nodes and properties to be parsed
            parse_node (root);

            int i = 0;
            string current;

            while (i < queue.size - 1) {
                i++;
                current = queue[i];
                if (current == "url" || current == "xmlUrl") {
                    i++;
                    feeds.add (queue[i]);
                }
            }

            string[] feeds_array = feeds.to_array ();
            return feeds_array;
        }

        /*
         * Parse the feed starting at a node (recursively called)
         */
        private void parse_node (Xml.Node* node) {

            // Loop over the passed node's children

            for (Xml.Node* iter = node->children; iter != null; iter = iter->next) {

                // Spaces between tags are also nodes, discard them
                if (iter->type != Xml.ElementType.ELEMENT_NODE) {
                    continue;
                }

                // Get the node's name
                string node_name = iter->name;
                queue.add (node_name);

                // Get the node's content with <tags> stripped
                string node_content = iter->get_content ();
                queue.add (node_content);

                // Now parse the node's properties (attributes) ...
                parse_properties (iter);

                // Followed by its children nodes
                parse_node (iter);
            }
        }

        /*
         * Parse the properties of a node
         */
        private void parse_properties (Xml.Node* node) {

            // Loop over the passed node's properties (attributes)
            for (Xml.Attr* prop = node->properties; prop != null; prop = prop->next) {

                string attr_name = prop->name;
                queue.add (attr_name);

                string attr_content = prop->children->content;
                queue.add (attr_content);

            }
        }

        /*
         * Re-parses the feed for a given podcast and finds episodes newer than the previous newest episode
         */
        public int update_feed (Podcast podcast) throws GLib.Error {

            Gee.ArrayList<Episode> new_episodes = new Gee.ArrayList<Episode> ();
            bool previous_found = false;

            queue.clear ();
            Episode previous_newest_episode = null;

            if (podcast.episodes.size > 0) {
                previous_newest_episode = podcast.episodes[0];
            }

            string path = podcast.feed_uri;

            // Call the Xml.Parser to parse the file, which returns an unowned reference
            Xml.Doc* doc;

            if (SoupClient.valid_http_uri (path)) {
                doc = XmlUtils.parse_string (soup_client.request_as_string (HttpMethod.GET, path));
            } else {
                doc = Xml.Parser.parse_file (path);

                // Make sure that it didn't return a null reference
                if (doc == null) {
                    throw new LeopodUpdateError.NETWORK_ERROR (
                        "Error opening file %s. Parser returned null.".printf (path)
                    );
                }
            }

            // Get the root node
            Xml.Node* root = doc->get_root_element ();

            // Make sure that it didn't return a null reference, either
            if (root == null) {

                // If it did, free the document manually (since unowned)
                delete doc;
                throw new LeopodUpdateError.NETWORK_ERROR ("The XML file '%s' is empty".printf (path));
            }


            // Parse the root node, which in turn will cause all nodes and properties to be parsed
            parse_node (root);

            if (root->name == "feed") {
                new_episodes = create_podcast_from_queue_atom_new_episodes (root, podcast, previous_newest_episode);
            } else {
                int i = 0;

                while ( i < queue.size && !previous_found) {

                    if (queue[i] == "item") {

                        // Create a new episode
                        string title = null;
                        string uri = null;
                        string description = null;
                        string date_released = null;
                        string guid = null;
                        string link = null;
                        string next_item_in_queue = null;


                        while (next_item_in_queue != "item" && i < queue.size - 1) {
                            i++;
                            next_item_in_queue = queue[i];
                            if (next_item_in_queue == "title") {
                                i++;
                                title = queue[i];
                            }
                            else if (next_item_in_queue == "enclosure") {
                                bool uri_found = false;
                                bool type_found = false;

                                // Because different podcasts enclose information differently,
                                // we must individually search for both the uri and the type
                                while (uri_found != true || type_found != true) {
                                    // Look at next item
                                    i++;

                                    if (queue[i] == "url") {

                                        i++;
                                        uri = queue[i];
                                        uri_found = true;

                                    } else if (queue[i] == "type") {
                                        i++;

                                        string typestring = queue[i].slice (0, 5);
                                        if (podcast.content_type == MediaType.UNKNOWN) {
                                            if (typestring == "audio") {
                                                podcast.content_type = MediaType.AUDIO;
                                            } else if (typestring == "video") {
                                                podcast.content_type = MediaType.VIDEO;
                                            } else {
                                                podcast.content_type = MediaType.UNKNOWN;
                                            }
                                        }
                                        type_found = true;
                                    }
                                }
                            }
                            else if (next_item_in_queue == "pubDate") {
                                i++;

                                date_released = queue[i];
                                //episode.set_datetime_from_pubdate ();

                            }
                            else if (next_item_in_queue == "summary") {
                                // Save the summary as description if we haven't found a description yet.
                                // Subsequent descriptions will overwrite this.
                                if (description.char_count () == 0) {
                                    i++;
                                    description = queue[i];
                                }
                            }
                            else if (next_item_in_queue == "description") {
                                i++;
                                description = queue[i];
                            } else if (next_item_in_queue == "guid") {
                                i++;
                                guid = queue[i];
                            } else if (next_item_in_queue == "link") {
                                i++;
                                link = queue[i];
                            }

                        }

                        Episode episode = new Episode(
                            title, uri, date_released, description, guid, link
                        );

                        if (previous_newest_episode != null) {
                            if (episode.title == previous_newest_episode.title.replace ("%27", "'")) {
                                previous_found = true;
                            } else {
                                new_episodes.add (episode);
                            }
                        } else {
                            new_episodes.add (episode);
                        }
                    }

                    // Otherwise, simply increment and keep going
                    else {
                        i++;
                    }
                }
            }

            // Iterate through the arraylist of new episodes

            // Keep in mind that the newest episode is on the bottom, so go in reverse order
            for (int index = new_episodes.size - 1; index >= 0; index--) {
                podcast.add_episode (new_episodes[index]);
            }

            int episodes_added = new_episodes.size;
            new_episodes = null;

            // Free up the space from the root node
            delete root;

            return episodes_added;
        }
    }

    /*
     * This method collects the episodes from atom xml file.
     */
    private ObservableArrayList<Episode> create_podcast_from_queue_atom_new_episodes (
        Xml.Node* node,
        Podcast podcast,
        Episode? previous_newest_episode
    ) {

        bool previous_found = false;
        ObservableArrayList<Episode> new_episodes = new ObservableArrayList<Episode> (); //array of new episodes
        ObservableArrayList<Episode> episodes = new ObservableArrayList<Episode> (); // array of episodes from xml

        /* Create the new podcast object */
        for (Xml.Node* iter = node->children; iter != null ; iter = iter->next) {
            if (iter->name != "entry") {
                continue;
            }

            /* Creating a Episode with values from <entry> tag. */
            string title = null;
            string description = null;
            string date_released = null;
            string uri = null;
            string guid = null;
            string link = null;

            for (Xml.Node* iterEntry = iter->children; iterEntry != null; iterEntry = iterEntry->next) {
                switch (iterEntry->name) {
                    case "title":
                        title= iterEntry->get_content ();
                        break;
                    case "content":
                        description= iterEntry->get_content ();
                        break;
                    case "updated":
                        GLib.Time tm = GLib.Time ();
                        tm.strptime ( iterEntry->get_content (), "%Y-%m-%dT%H:%M:%S%Z");
                        date_released=tm.format ("%a, %d %b %Y %H:%M:%S %Z");
                        break;
                    case "link":
                        for (Xml.Attr* propEntry = iterEntry->properties; propEntry != null; propEntry = propEntry->next) {  // vala-lint=line-length
                            string attr_name = propEntry->name;
                            if (attr_name == "href") {
                                uri=propEntry->children->content;
                                link = uri;
                            } else if (
                                attr_name == "type" && podcast != null
                                && podcast.content_type != MediaType.UNKNOWN
                            ) {
                                if (propEntry->children->content.contains ("audio/")) {
                                    podcast.content_type = MediaType.AUDIO;
                                } else if (propEntry->children->content.contains ("video/")) {
                                    podcast.content_type = MediaType.VIDEO;
                                }
                            }
                        }
                        break;
                    case "id":
                        guid = iterEntry->get_content ();
                        break;
                    default:
                        break;
                }
            }
            Episode entry = new Episode(
                title, uri, date_released, description, guid, link
            );

            episodes.add (entry);
        }

        for (int i=episodes.size; i > 0 && !previous_found; i--) {
            Episode entry=episodes[i - 1];

            if (previous_newest_episode != null) {
                if (entry.title == previous_newest_episode.title.replace ("%27", "'")) {
                    previous_found = true;
                } else {
                    new_episodes.add (entry);
                }
            } else {
                new_episodes.add (entry);
            }
        }

        return new_episodes;
    }

    /*
     * This method, using XML structure of a atom file, populates attributes
     * for a podcasts and its entries.
     */
    private Podcast create_podcast_from_queue_atom ( Xml.Node* node) {

        Podcast podcast = null;
        ObservableArrayList<Episode> episodes = new ObservableArrayList<Episode>();

        string name = null;
        string description = null;
        string feed_uri = null;
        string remote_art_uri = null;
        License license = License.UNKNOWN;
        MediaType content_type = MediaType.UNKNOWN;

        for (Xml.Node* iter = node->children; iter != null; iter = iter->next) {
            /* Assigning podcast properties... */
            switch (iter->name) {
                case "title":
                    name= iter->get_content ();
                    break;
                case "subtitle":
                    description= iter->get_content ();
                    break;
                case "logo":
                    remote_art_uri= iter->get_content ();
                    break;
                case "rights":
                    if (iter->get_content ().index_of ("cc-") == 0) {
                        license = License.CC;
                    } else {
                        license = License.UNKNOWN;
                    }
                    break;
                case "link":
                    for (Xml.Attr* prop = iter->properties; prop != null; prop = prop->next) {
                        if (prop->name == "href") {
                            podcast.feed_uri=prop->children->content;
                        }
                    }
                    break;
                default:
                    break;
            }
        }

        podcast = new Podcast(name, description, feed_uri, remote_art_uri, license, content_type);

        episodes = create_podcast_from_queue_atom_new_episodes (node, podcast, null);

        podcast.add_episodes(episodes);

        return podcast;
    }
}

