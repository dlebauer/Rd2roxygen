#' Parse the input Rd file to a list
#'
#' This function uses the function \code{parse_Rd} in the \pkg{tools} package to
#' parse the Rd file.
#' @param path the path of the Rd file
#' @return a named list containing the documentation sections as strings
#' @export
#' @author Hadley Wickham; modified by Yihui Xie <\url{http://yihui.name}>
#' @examples
#' rd.file = system.file('examples', 'parse_and_save.Rd', package='Rd2roxygen')
#' parse_file(rd.file)
parse_file <- function(path) {
  rd <- tools::parse_Rd(path)

  tags <- sapply(rd, tag)
  tags <- gsub("\\\\", "", tags)
  names(rd) <- tags

  # Remove top-level text strings - just line breaks between sections
  rd <- rd[tags != "TEXT"]

  out <- list()
  # Title, description, value and examples, need to be stitched into a
  # single string.
  out$title <- reconstruct(untag(rd$title))
  out$docType <- reconstruct(untag(rd$docType))
  out$usage <- reconstruct(untag(rd$usage))
  out$desc <- gsub("$\n+|\n+^", "", reconstruct(untag(rd$description)))
  out$details <- reconstruct(untag(rd$details))
  out$section <- paste(reconstruct(untag(rd$section[1])),
                       reconstruct(untag(rd$section[-1])), sep = ': ')
  out$format <- reconstruct(untag(rd$format))
  out$note <- reconstruct(untag(rd$note))
  out$author <- gsub('@', '@@', reconstruct(untag(rd$author)))
  out$seealso <- reconstruct(untag(rd$seealso))
  out$references <- reconstruct(untag(rd$references))
  out$source <- reconstruct(untag(rd$source))

  out$examples <- reconstruct(untag(rd$examples))

  # Join together aliases and keywords
  out$name <- reconstruct(untag(rd$name))
  out$aliases <- unname(sapply(rd[names(rd) == "alias"], "[[", 1))
  # If the only alias is the name, then skip it
  if (identical(out$aliases, out$name)) {
    out$aliases <- NULL
  }
  out$keywords <- unname(sapply(rd[names(rd) == "keyword"], "[[", 1))

  # Pull apart arguments
  arguments <- rd$arguments
  arguments <- arguments[sapply(arguments, tag) != "TEXT"]
  out$params <- unlist(sapply(arguments, function(argument) {
    if (tag(argument) != '\\item') return(NULL)
    paste(if (tag(argument[[1]][[1]]) == "\\dots")
      "\\dots" else gsub(' +', '', argument[[1]]),
          reconstruct(argument[[2]]))
  }))

  # Pull apart general return value description and return items
  value <- rd$value
  is.item <- sapply(value, tag) == "\\item"
  out$value <- reconstruct(untag(value[!is.item]))
  # Pull apart return items
  out$valueItems <- unlist(sapply(value[is.item], function(item) {
    paste(if (tag(item[[1]][[1]]) == "\\dots")
      "\\dots" else gsub(' +', '', item[[1]]),
          reconstruct(item[[2]]))
  }))

  out
}


#' Create the roxygen documentation
#'
#' The parsed information is converted to a vector of roxygen tags.
#' @param info the named list of the parsed documentation
#' @param usage logical: whether to include the usage section in the output
#'   (this can be useful when there are multiple functions in a single usage
#'   section, but generally it is not necessary because roxygen can generate the
#'   usage section automatically)
#' @export
#' @return a character vector
#' @author Hadley Wickham; modified by Yihui Xie <\url{http://yihui.name}>
#' @examples
#' rd.file = system.file('examples','parse_and_save.Rd',package='Rd2roxygen')
#' options(roxygen.comment = "##' ")
#' create_roxygen(parse_file(rd.file))
create_roxygen <- function(info, usage = FALSE) {
  c(comment_line(info$title),
    comment_line(),
    comment_line(info$desc),
    comment_line(),
    comment_line(info$details),
    comment_line(),
    if (!is.null(info$docType) &&
      (info$docType %in% c('package', 'data', 'methods', 'class')))
      comment_tag("@name", info$name),
    comment_tag("@aliases", paste(info$aliases, collapse = " ")),
    comment_tag("@docType", info$docType),
    if (usage) comment_tag("@usage", info$usage),
    comment_tag("@param", info$params),
    comment_tag("@format", info$format),
    comment_tag("@return", info$value),
    comment_tag("@returnItem", info$valueItem),
    comment_tag("@note", info$note),
    comment_tag("@section", info$section),
    comment_tag("@author", info$author),
    comment_tag("@seealso", info$seealso),
    comment_tag("@references", info$references),
    comment_tag("@source", info$source),
    comment_tag("@keywords", paste(info$keywords, collapse = " ")),
    if (!is.null(info$examples)) {
      c(comment_line("@examples\n"),
        paste(comment_prefix(),
              gsub("\n", paste("\n", comment_prefix(), sep = ""),
                   info$examples),
              sep = ""))
    },
    if (!is.null(info$docType) && (info$docType %in% c('package', 'data')))
      "NULL", "\n")
}

#' Parse the input Rd file and save the roxygen documentation into a file
#' @param path the path of the Rd file
#' @param file the path to save the roxygen documentation
#' @param usage logical: whether to include the usage section in the output
#' @return a character vector if \code{file} is not specified, or write the
#'   vector into a file
#' @export
#' @author Hadley Wickham; modified by Yihui Xie <\url{http://yihui.name}>
parse_and_save <- function(path, file, usage = FALSE) {
  parsed <- parse_file(path)
  output <- create_roxygen(parsed, usage = usage)
  if (missing(file)) output else
    cat(paste(output, collapse = "\n"), file = file)
}


#' Convert all the Rd files of a package to roxygen comments
#'
#' This function takes a package root directory, parses all its Rd files under
#' the man directory and update the corresponding R source code by inserting
#' roxygen documentation in to the R scripts.
#' @param pkg the root directory of the package
#' @param export one of "none", "all", or "namespace"; if "none", the \code{export} 
#' tag is not added to any functions; if "all", adds \code{export} to all documented functions;
#' if "namespace", adds \code{export} to functions explicitly exported in the existing NAMESPACE
#' @param nomatch the file name (base name only) to use when an object in the Rd
#'   file is not found in any R source files (typically this happens to the data
#'   documentation); if not specified, the default will be `pkg'-package.R
#' @param usage logical: whether to include the usage section in the output
#' @return NULL (but the process of conversion will be printed on screen)
#' @note ESS users may use \code{options(roxygen.comment = "##' ")} to ensure
#'   the generated roxygen comments begin with \code{"##' "}, which is the
#'   default setting in Emacs/ESS.
#'
#'   Re-run this function on a package will remove the previous roxygen comments
#'   before functions in R scripts.
#' @export
#' @author Yihui Xie <\url{http://yihui.name}>
#' @examples
#' ## a demo package
#' pkg = system.file('examples', 'pkgDemo', package = 'Rd2roxygen')
#' file.copy(pkg, tempdir(), recursive = TRUE)  # copy to temp dir first
#' od = setwd(tempdir())
#'
#' ## take a look at original R scripts
#' file.show('pkgDemo/R/foo.R')
#'
#' options(roxygen.comment = "##' ")
#'
#' ## convert Rd's under man to roxygen comments
#' Rd2roxygen(file.path(tempdir(), 'pkgDemo'))
#'
#' file.show('pkgDemo/R/foo.R')  # what happened to foo.R and bar.R?
#'
#' setwd(od)  # restore working directory
Rd2roxygen <- function(pkg, nomatch, export = "none", usage = FALSE) {
  if (!all(c('man', 'R') %in% list.files(pkg)))
    stop("'pkg' has to be the root directory of a source package")
  man.dir <- file.path(pkg, 'man')
  R.dir <- file.path(pkg, 'R')
  files <- list.files(man.dir, '\\.[Rr]d$')
  if (missing(nomatch))
    nomatch <- paste(basename(pkg), '-package.R', sep = '')
  unlink(p <- file.path(R.dir, nomatch))
  for (f in files) {
    timestamp()
    parsed <- parse_file(file.path(man.dir, f))
    Rd <- create_roxygen(parsed, usage = usage)
    Rd <- Rd[Rd != '\n']
    message('parsed: ', f)
    fname <- parsed$name
    tryf <- paste(fname, c('.R', '.r'), sep = '')
    tryf <- unique(c(tryf[file.exists(file.path(R.dir, tryf))],
                     list.files(R.dir, '\\.[Rr]$')))
    idx <- integer(0)
    ## should not search data/package names in R scripts
    if (isTRUE(parsed$docType %in% c('data', 'package')))
      tryf <- NULL else message("looking for the object '", fname, "' in:")
    for (i in tryf) {
      r <- file.path(R.dir, i)
      idx <- grep(sprintf('^[[:space:]]*(`|"|\'|)(%s)(`|"|\'|)[[:space:]]*(<-|=)',
                          gsub('\\.', '\\\\.', fname)),
                  (r.Rd <- readLines(r, warn = FALSE)))
      message('  ', i, ': ', appendLF = FALSE)
      message(ifelse(length(idx), paste('line', idx), 'not found'))
      if (length(idx)) break
    }
    if (length(idx)) {
      idx <- idx[1]  # only use the first match
      if (idx <= 1) r.Rd <- c(Rd, r.Rd) else {
        ## remove existing roxygen comments
        j <- 0
        for(i in (idx - 1):1) {
          if (grepl("^[#]+'", r.Rd[i])) j <- j + 1 else break
        }
        if (j > 0) {
          r.Rd <- r.Rd[-(idx - seq_len(j))]
          idx <- idx - j
        }
        r.Rd <- append(r.Rd, c('\n', Rd), idx - 1)
        while (r.Rd[1] %in% c('', '\n')) r.Rd <- r.Rd[-1]
      }
      cat(r.Rd, file = r, sep = '\n')
      message(r, ' updated')
    } else {
      if (tail(Rd, 1) != 'NULL') Rd <- c(Rd, 'NULL')
      cat(c('\n', Rd), '\n\n', file = p, sep = '\n', append = TRUE)
      message("unmatched object '", fname, "' written into ", p)
    }
    ### exporting functions
    ### https://github.com/yihui/Rd2roxygen/issues/10
    if(!export %in% c("none", "any", "namespace")){
      message("export setting", export, "not implemented")
    }
    if(export == "none"){
      message("no functions will be exported; need to manually add @export to exported functions")
      if(export == "all"){
        ### export all functions by default; https://gist.github.com/4666066
        for( file in list.files(file.path(pkg, "./R"), full.names = TRUE)) {
          doc <- scan( what=character(), sep="\n", file, blank.lines.skip = FALSE)
          returns <- which(!grepl("returnItem", doc) & grepl("@return", doc))
          if(length(returns) > 0){
            doc[returns] <- gsub("##' @return", paste("##' @export\n##' @return"), doc[returns])
            doc <- paste(doc, collapse="\n")
            cat(doc, file = file)
          }
        }
        if (export == "namespace"){
          ## from github user cdrv and http://stackoverflow.com/a/14587886/513006
          NAMESPACE <- readLines("NAMESPACE")
          exported_fns <- grep( "^export\\(", NAMESPACE, value=TRUE )
          exported_fn_names <- gsub( "export\\((.*)\\)", "\\1", exported_fns )
          fn_match_re <- paste("^", exported_fn_names, " ?<- ?", sep="")
          
          for( file in list.files("./R", full.names=TRUE) ) {
            doc <- readLines( file )
            for( i in seq_along(doc) ) {
              if( any( sapply( fn_match_re, function(x) {
                length( grep( x, doc[i] ) ) > 0
              } ) ) ) {
                doc[i] <- paste( "##' @export", doc[i], sep="\n" )
              }
            }
            writeLines( doc, file )
          }
        }
      }
      
    }  
    message('\n')
    flush.console()
  }
}
