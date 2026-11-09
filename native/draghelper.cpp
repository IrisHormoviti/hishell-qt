#include "draghelper.h"

#include <QDrag>
#include <QImage>
#include <QMimeData>
#include <QPixmap>
#include <QQmlEngine>
#include <QUrl>
#include <QTimer>

DragHelper::DragHelper(QObject *parent) : QObject(parent) {}

void DragHelper::setSpringTarget(const QString &path)
{
	if (QUrl(m_uri).toLocalFile() == path)
		return;
	m_spring = path;
	QTimer::singleShot(700, this, [this] {
		if (!m_spring.isEmpty())
			emit springRequested(m_spring);
	});
}

void DragHelper::clearSpringTarget()
{
	m_spring.clear();
}

bool DragHelper::isSource(const QString &path) const
{
	return QUrl(m_uri).toLocalFile() == path;
}

void DragHelper::startDrag(const QString &uri, const QString &imageUrl)
{
	m_uri = uri;
	QTimer::singleShot(0, this, [this, uri, imageUrl] {
		performDrag(uri, imageUrl);
	});
}

void DragHelper::performDrag(const QString &uri, const QString &imageUrl)
{
	QDrag drag(this);
	QMimeData *mime = new QMimeData;
	mime->setUrls({QUrl(uri)});
	mime->setText(uri);
	drag.setMimeData(mime);

	if (!imageUrl.isEmpty()) {
		const QUrl url(imageUrl);
		const QImage image(url.isLocalFile() ? url.toLocalFile() : imageUrl);
		if (!image.isNull())
			drag.setPixmap(QPixmap::fromImage(image));
	}

	drag.exec(Qt::CopyAction | Qt::MoveAction | Qt::LinkAction);
	emit dragFinished();
}

static QObject *dragHelperProvider(QQmlEngine *, QJSEngine *)
{
	return new DragHelper;
}

extern "C" void hishell_register_drag_helper()
{
	qmlRegisterSingletonType<DragHelper>("NativeDrag", 1, 0, "DragHelper",
		dragHelperProvider);
}
