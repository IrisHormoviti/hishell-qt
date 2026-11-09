#include "draghelper.h"

#include <QDrag>
#include <QImage>
#include <QMimeData>
#include <QPixmap>
#include <QQmlEngine>
#include <QQuickItemGrabResult>
#include <QTimer>
#include <QUrl>

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
	QImage image;
	if (!imageUrl.isEmpty()) {
		const QUrl url(imageUrl);
		image.load(url.isLocalFile() ? url.toLocalFile() : imageUrl);
	}
	m_uri = uri;
	QTimer::singleShot(0, this, [this, uri, image] {
		performDrag(uri, image);
	});
}

void DragHelper::startDragFromGrab(QObject *grab, const QString &uri)
{
	auto *result = qobject_cast<QQuickItemGrabResult *>(grab);
	const QImage image = result ? result->image() : QImage();
	m_uri = uri;
	QTimer::singleShot(0, this, [this, uri, image] {
		performDrag(uri, image);
	});
}

void DragHelper::performDrag(const QString &uri, const QImage &image)
{
	QDrag drag(this);
	QMimeData *mime = new QMimeData;
	mime->setUrls({QUrl(uri)});
	mime->setText(uri);
	drag.setMimeData(mime);

	if (!image.isNull()) {
		const QPixmap pixmap = QPixmap::fromImage(image);
		drag.setPixmap(pixmap);
		drag.setHotSpot(pixmap.rect().center());
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
